require 'digest/sha1'

class QstServerChannel < Channel
  include ActionView::Helpers::DateHelper

  has_many :qst_outgoing_messages, :foreign_key => 'channel_id'

  validates_presence_of :password

  configuration_accessor :password, :password_confirmation, :salt

  before_validation :reset_password, :if => lambda { persisted? && password.blank? }
  before_create :hash_password
  before_update :hash_password, :if => lambda { salt.blank? }

  validate :validate_password_confirmation

  attr_accessor :ticket_code, :ticket_message
  before_save :ticket_record_password, :if => lambda { ticket_code.present? }
  after_create :ticket_mark_as_complete, :if => lambda { ticket_code.present? }

  def self.title
    "QST server (local gateway)"
  end

  def self.default_protocol
    'sms'
  end

  def handle(msg)
    outgoing = QstOutgoingMessage.new
    outgoing.channel_id = id
    outgoing.ao_message_id = msg.id
    outgoing.save
  end

  def authenticate(password)
    self.password == encode_password(decoded_salt, password)
  end

  def info
    "Last activity: " + (last_activity_at ? "#{time_ago_in_words(last_activity_at)} ago" : 'never')
  end

  def has_connection?
    true
  end

  private

  def reset_password
    old_configuration = configuration_was.dup
    self.password = self.password_confirmation = old_configuration[:password]
    self.salt = old_configuration[:salt]
  end

  def hash_password
    self.salt = ActiveSupport::SecureRandom.base64 8
    self.password = self.password_confirmation = encode_password(decoded_salt, password)
  end

  def decoded_salt
    Base64.decode64 salt
  end

  def encode_password(salt, password)
    Base64.encode64(Digest::SHA1.digest(salt + Iconv.conv('ucs-2le', 'utf-8', password))).strip
  end

  def validate_password_confirmation
    errors.add :password, 'does not match confirmation' if password_confirmation && password != password_confirmation
  end

  def ticket_record_password
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
    ticket = Ticket.complete ticket_code, { :channel => self.name, :account => self.account.name, :password => @password_input, :message => self.ticket_message }
  end

  def common_to_x_attributes
    attributes = super
    [:ticket_code, :ticket_message].each do |sym|
      value = send sym
      attributes[sym] = value if value.present?
    end
    attributes
  end
end
