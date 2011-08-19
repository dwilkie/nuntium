require 'digest/sha2'

class Channel < ActiveRecord::Base
  # Channel directions
  Incoming = 1
  Outgoing = 2
  Bidirectional = Incoming + Outgoing

  belongs_to :account
  belongs_to :application

  has_many :ao_messages, :class_name => 'AOMessage'
  has_many :at_messages, :class_name => 'ATMessage'
  has_many :qst_outgoing_messages, :class_name => 'QSTOutgoingMessage'
  has_many :smpp_message_parts
  has_many :twitter_channel_statuses
  has_many :address_sources
  has_many :cron_tasks, :as => :parent, :dependent => :destroy # TODO: Tasks are not being destroyed

  serialize :configuration, Hash
  serialize :restrictions
  serialize :ao_rules
  serialize :at_rules

  attr_accessor :ticket_code, :ticket_message
  attr_accessor :throttle_opt

  validates_presence_of :name, :protocol, :kind, :account
  validates_format_of :name, :with => /^[a-zA-Z0-9\-_]+$/, :message => "can only contain alphanumeric characters, '_' or '-' (no spaces allowed)", :unless => proc {|c| c.name.blank?}
  validates_uniqueness_of :name, :scope => :account_id, :message => 'has already been used by another channel in the account'
  validates_inclusion_of :direction, :in => [Incoming, Outgoing, Bidirectional], :message => "must be 'incoming', 'outgoing' or 'bidirectional'"
  validates_numericality_of :throttle, :allow_nil => true, :only_integer => true, :greater_than_or_equal_to => 0
  validates_numericality_of :ao_cost, :greater_than_or_equal_to => 0, :allow_nil => true
  validates_numericality_of :at_cost, :greater_than_or_equal_to => 0, :allow_nil => true

  before_save :ticket_record_password
  after_create :ticket_mark_as_complete

  validate :handler_check_valid
  before_validation :handler_before_validation
  before_save :handler_before_save
  after_create :handler_after_create
  after_update :handler_after_update
  before_destroy :handler_before_destroy

  scope :enabled, where(:enabled => true)
  scope :disabled, where(:enabled => false)
  scope :outgoing, where(:direction => [Outgoing, Bidirectional])
  scope :incoming, where(:direction => [Incoming, Bidirectional])

  include CronTask::CronTaskOwner

  def self.kinds
    @@kinds ||= begin
      # Load all channel handlers
      Dir.glob("#{Rails.root}/app/models/**/*_channel_handler.rb").each do |file|
        eval(ActiveSupport::Inflector.camelize(file[file.rindex('/') + 1 .. -4]))
      end

      Object.subclasses_of(ChannelHandler).select do |clazz|
        # Skip some abstract ones
        clazz.name != 'GenericChannelHandler' && clazz.name != 'ServiceChannelHandler'
      end.map do |clazz|
        # Put the title and kind in array
        [clazz.title, clazz.kind]
      end.sort do |a1, a2|
        # And sort by title
        a1[0] <=> a2[0]
      end
    end
    @@kinds.map{|x| [x[0].dup, x[1].dup]}
  end

  def self.sort_candidate!(chans)
    chans.each{|x| x.configuration[:_p] = x.priority + rand}
    chans.sort! do |x, y|
      result = x.configuration[:_p].floor <=> y.configuration[:_p].floor
      result = ((x.paused ? 1 : 0) <=> (y.paused ? 1 : 0)) if result == 0
      result = x.configuration[:_p] <=> y.configuration[:_p] if result == 0
      result
    end
  end

  def route_ao(msg, via_interface, options = {})
    simulate = options[:simulate]
    dont_save = options[:dont_save]

    ThreadLocalLogger << "Message routed to channel '#{name}'"

    # Assign cost
    msg.cost = ao_cost if ao_cost.present?

    # Apply AO Rules
    apply_ao_rules msg

    # Discard the message if the rules canceled the message
    if msg.state == 'canceled'
      msg.channel = self
      msg.state = 'canceled'
      msg.save! unless simulate || dont_save

      ThreadLocalLogger << "Message was canceled by channel ao rules."
      logger.info :application_id => msg.application_id, :channel_id => self.id, :ao_message_id => msg.id, :message => ThreadLocalLogger.result unless simulate
      return
    end

    # Discard the message if the 'from' and 'to' are the same
    if msg.from == msg.to
      msg.channel = self
      msg.state = 'failed'
      msg.save! unless simulate || dont_save

      ThreadLocalLogger << "Message 'from' and 'to' addresses are the same. The message will be discarded."
      logger.warning :application_id => msg.application_id, :channel_id => self.id, :ao_message_id => msg.id, :message => ThreadLocalLogger.result unless simulate
      return
    end

    # Discard message if the 'to' address is not valid
    if not msg.to.valid_address?
      msg.state = 'failed'
      msg.save! unless simulate || dont_save

      ThreadLocalLogger << "Message 'to' address is invalid. The message will be discarded."
      logger.warning :application_id => msg.application_id, :channel_id => self.id, :ao_message_id => msg.id, :message => ThreadLocalLogger.result unless simulate
      return
    end

    # Save the message
    msg.channel = self
    msg.state = 'queued'
    msg.save! unless simulate || dont_save

    unless simulate
      logger.info :application_id => msg.application_id, :channel_id => self.id, :ao_message_id => msg.id, :message => ThreadLocalLogger.result

      # Handle the message
      handle msg
    end
  end

  def apply_ao_rules(msg)
    ao_routing_res = RulesEngine.apply(msg.rules_context, self.ao_rules)
    if ao_routing_res.present?
      ThreadLocalLogger << "Applying channel ao rules..."
      msg.original = msg.merge ao_routing_res
    end
  end

  def can_route_ao?(msg)
    # Check that each custom attribute is present in this channel's restrictions (probably augmented with handler's)
    handler_restrictions = self.handler.restrictions

    msg.custom_attributes.each_multivalue do |key, values|
      channel_values = handler_restrictions[key]
      next unless channel_values.present?

      channel_values = [channel_values] unless channel_values.kind_of? Array

      return false unless values.any?{|v| channel_values.include? v}
    end

    handler_restrictions.each_multivalue do |key, values|
      next if values.include? ''
      return false unless msg.custom_attributes.has_key? key
    end

    return true
  end

  def is_outgoing?
    direction == Outgoing || direction == Bidirectional
  end

  def is_incoming?
    direction == Incoming || direction == Bidirectional
  end

  def configuration
    self[:configuration] = {} if self[:configuration].nil?
    self[:configuration]
  end

  def restrictions
    self[:restrictions] = ActiveSupport::OrderedHash.new if self[:restrictions].nil?
    self[:restrictions]
  end

  def clear_password
    self.handler.clear_password if self.handler.respond_to?(:clear_password)
  end

  def handle(msg)
    self.handler.handle msg
  end

  def route_at(msg)
    account.route_at msg, self
  end

  def alert(message)
    return if account.alert_emails.blank?

    logger.error :channel_id => self.id, :message => message
    AlertMailer.error(account, "Error in account #{account.name}, channel #{self.name}", message).deliver
  end

  def handler
    if kind.nil?
      nil
    else
      eval(ActiveSupport::Inflector.camelize(kind) + 'ChannelHandler.new(self)')
    end
  end

  def info
    return self.handler.info if self.handler.respond_to?(:info)
    return ''
  end

  def direction=(value)
    if value.kind_of? String
      if value.integer?
        self[:direction] = value.to_i
      else
        self[:direction] = Channel.direction_from_text(value)
      end
    else
      self[:direction] = value
    end
  end

  def direction_text
    case direction
    when Incoming
      'incoming'
    when Outgoing
      'outgoing'
    when Bidirectional
      'bidirectional'
    else
      'unknown'
    end
  end

  def self.direction_from_text(direction)
    case direction.downcase
    when 'incoming'
      Incoming
    when 'outgoing'
      Outgoing
    when 'bidirectional'
      Bidirectional
    else
      -1
    end
  end

  def check_valid_in_ui
    @check_valid_in_ui = true
  end

  def throttle_opt
    self.throttle.nil? ? 'off' : 'on'
  end

  def logger
    @logger = AccountLogger.new self.account_id
  end

  def to_xml(options = {})
    options[:indent] ||= 2
    xml = options[:builder] ||= Builder::XmlMarkup.new(:indent => options[:indent])
    xml.instruct! unless options[:skip_instruct]

    attributes = common_to_x_attributes

    xml.channel attributes do
      xml.configuration do
        configuration.each do |name, value|
          next if value.blank?
          is_password = name.to_s.include?('password') || name.to_s == 'salt'
          next if is_password and (options[:include_passwords].nil? or options[:include_passwords] === false)
          xml.property :name => name, :value => value
        end
      end
      xml.restrictions do
        restrictions.each_multivalue do |name, values|
          values.each do |value|
            xml.property :name => name, :value => value
          end
        end
      end unless restrictions.empty?
      xml.ao_rules do
        RulesEngine.to_xml xml, ao_rules
      end unless ao_rules.nil?
      xml.at_rules do
        RulesEngine.to_xml xml, at_rules
      end unless at_rules.nil?
    end
  end

  def self.from_xml(hash_or_string)
    if hash_or_string.empty?
      tree = {:channel => {}}
    else
      tree = hash_or_string.kind_of?(Hash) ? hash_or_string : Hash.from_xml(hash_or_string)
    end
    tree = tree.with_indifferent_access
    Channel.from_hash tree[:channel], :xml
  end

  def as_json(options = {})
    options ||= {}

    attributes = common_to_x_attributes
    attributes[:configuration] = []
    configuration.each do |name, value|
      next if value.blank?
      is_password = name.to_s.include?('password') || name.to_s == 'salt'
      next if is_password && (options[:include_passwords].nil? || options[:include_passwords] === false)
      attributes[:configuration] << {:name => name, :value => value}
    end
    restrictions.each do |name, values|
      attributes[:restrictions] ||= []
      attributes[:restrictions] << {:name => name, :value => values}
    end unless restrictions.empty?
    attributes[:ao_rules] = ao_rules unless ao_rules.nil?
    attributes[:at_rules] = at_rules unless at_rules.nil?

    attributes
  end

  def self.from_json(hash_or_string)
    if hash_or_string.empty?
      tree = {}
    else
      tree = hash_or_string.kind_of?(Hash) ? hash_or_string.with_indifferent_access : JSON.parse(hash_or_string).with_indifferent_access
    end
    Channel.from_hash tree, :json
  end

  def merge(other)
    [:name, :kind, :protocol, :direction, :enabled, :priority, :configuration, :restrictions, :address, :ao_cost, :at_cost, :ao_rules, :at_rules].each do |sym|
      write_attribute sym, other.read_attribute(sym) if !other.read_attribute(sym).nil?
    end
  end

  def has_connection?
    self.handler.has_connection?
  end

  def queued_ao_messages_count
    ao_messages.with_state('queued').count
  end

  private

  def ticket_record_password
    return unless ticket_code
    ticket = Ticket.find_by_code_and_status ticket_code, 'pending'
    if ticket.nil?
      errors.add(:ticket_code, "Invalid code")
      return false
    end
    self.address = ticket.data[:address]
    @password_input = configuration[:password]
    return true
  end

  def ticket_mark_as_complete
    return unless ticket_code
    ticket = Ticket.complete ticket_code, { :channel => self.name, :account => self.account.name, :password => @password_input, :message => self.ticket_message }
  end

  def handler_check_valid
    self.handler.check_valid if self.handler.respond_to?(:check_valid)
    if !@check_valid_in_ui.nil? and @check_valid_in_ui
      self.handler.check_valid_in_ui if self.handler.respond_to?(:check_valid_in_ui)
    end
  end

  def handler_before_validation
    self.handler.try :before_validation
    true
  end

  def handler_before_save
    self.handler.before_save
    true
  end

  def handler_after_create
    self.handler.on_create
  end

  def handler_after_update
    if self.enabled_changed?
      if self.enabled
        self.handler.on_enable
      else
        self.handler.on_disable
      end
    elsif self.paused_changed?
      if self.paused
        self.handler.on_pause
      else
        self.handler.on_resume
      end
    elsif self.connected_changed?
      # Do nothing
    else
      self.handler.on_changed
    end
    true
  end

  def handler_before_destroy
    self.handler.on_destroy
    true
  end

  def common_to_x_attributes
    attributes = {}
    [:name, :kind, :protocol, :enabled, :priority, :address, :ao_cost, :at_cost, :last_activity_at, :ticket_code, :ticket_message].each do |sym|
      value = send sym
      attributes[sym] = value if value.present?
    end
    attributes[:direction] = direction_text unless direction_text == 'unknown'
    attributes[:application] = application.name if application_id
    attributes
  end

  def self.from_hash(hash, format)
    hash = hash.with_indifferent_access

    chan = Channel.new
    [:name, :kind, :protocol, :priority, :address, :ao_cost, :at_cost].each do |sym|
      chan.send "#{sym}=", hash[sym]
    end
    chan.enabled = hash[:enabled].to_b
    chan.direction = hash[:direction] if hash[:direction]
    chan.ticket_code = hash[:ticket_code] if hash[:ticket_code]
    chan.ticket_message = hash[:ticket_message] if hash[:ticket_message]

    hash_config = hash[:configuration] || {}
    hash_config = hash_config[:property] || [] if format == :xml and hash_config[:property]
    hash_config = [hash_config] unless hash_config.blank? or hash_config.kind_of? Array or hash_config.kind_of? String

    hash_config.each do |property|
      chan.configuration.store_multivalue property[:name].to_sym, property[:value]
    end unless hash_config.kind_of? String

    hash_restrict = hash[:restrictions] || {}
    hash_restrict = hash_restrict[:property] || [] if format == :xml and hash_restrict[:property]
    hash_restrict = [hash_restrict] unless hash_restrict.blank? or hash_restrict.kind_of? Array or hash_restrict.kind_of? String

    # force the empty hash at least, if the restrictions were specified
    # this is needed for proper merging when updating through api
    chan.restrictions if hash.has_key? :restrictions

    hash_restrict.each do |property|
      chan.restrictions.store_multivalue property[:name], property[:value]
    end unless hash_restrict.kind_of? String

    chan.ao_rules = RulesEngine.from_hash hash[:ao_rules], format if hash.has_key?(:ao_rules)
    chan.at_rules = RulesEngine.from_hash hash[:at_rules], format if hash.has_key?(:at_rules)

    chan
  end
end
