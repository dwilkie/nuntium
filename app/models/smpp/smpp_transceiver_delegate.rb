require 'iconv'

class SmppTransceiverDelegate
  
  EncodingCode = { "ascii" => 1, "latin1" => 3, "ucs-2be" => 8, "ucs-2le" => 8 }
  
  def initialize(transceiver, channel)
    @transceiver = transceiver
    @channel = channel
    @encodings = @channel.configuration[:mt_encodings].map { |x| encoding_endianized x }
  end
  
  def send_message(id, from, to, text)
    msg_text = nil
    msg_coding = nil
    
    # Select best encoding for the message
    @encodings.each do |encoding|
      iconv = Iconv.new(encoding, 'utf-8')
      msg_text = iconv.iconv(text) rescue next
      msg_coding = EncodingCode[encoding]
      break
    end
    
    @transceiver.send_mt(id, from, to, msg_text, {:data_coding => msg_coding})
  end
  
  def mo_received(transceiver, pdu)
    text = pdu.short_message
    
    # Use the message_payload optional parameter if present
    if text.length == 0 && pdu.optional_parameters && pdu.optional_parameters[0x0424]
      text = pdu.optional_parameters[0x0424].value
    end
    
    # Parse concatenated SMS from UDH
    if pdu.esm_class & 64 != 0
      udh = Udh.new(text)
      text = udh.skip text
      if udh[0]
        ref = udh[0][:reference_number]
        total = udh[0][:part_count]
        partn = udh[0][:part_number]
        return part_received(pdu.source_addr, pdu.destination_addr, pdu.data_coding, text, ref, total, partn)
      end
    end
    
    # Parse concatenated SMS from optional parameters (sar_*)
    if pdu.optional_parameters && pdu.optional_parameters[0x020c] && pdu.optional_parameters[0x020e] && pdu.optional_parameters[0x020f]
      ref = bytes_to_int pdu.optional_parameters[0x020c].value
      total = bytes_to_int pdu.optional_parameters[0x020e].value
      partn = bytes_to_int pdu.optional_parameters[0x020f].value
      return part_received(pdu.source_addr, pdu.destination_addr, pdu.data_coding, text, ref, total, partn)
    end
  
    create_at_message pdu.source_addr, pdu.destination_addr, pdu.data_coding, text
  end
  
  def create_at_message(source, destination, data_coding, text)
    msg = ATMessage.new
    msg.from = source.with_protocol 'sms'
    msg.to = destination.with_protocol 'sms'
    if @channel.configuration[:accept_mo_hex_string] == '1' and is_hex(text) 
      bytes = hex_to_bytes text
      iconv = Iconv.new('utf-8', ucs2_endianized)
      msg.subject = iconv.iconv bytes
    else
      source_encoding = case data_coding
        when 0: encoding_endianized(@channel.configuration[:default_mo_encoding])
        when 1: 'ascii'
        when 3: 'latin1'
        when 8: ucs2_endianized
      end
      
      if source_encoding
        iconv = Iconv.new('utf-8', source_encoding)
        msg.subject = iconv.iconv text
      else
        msg.subject = text
      end
    end
    
    @channel.accept msg
  end
  
  def part_received(source, destination, data_coding, text, ref, total, partn)
    
    
    conditions = ['channel_id = ? AND reference_number = ?', @channel.id, ref]
    parts = SmppMessagePart.all(:conditions => conditions)
    
    # If all other parts are here
    if parts.length == total-1
      # Add this new part, sort and get text
      parts.push SmppMessagePart.new(:part_number => partn, :text => text)
      parts.sort! { |x,y| x.part_number <=> y.part_number }
      text = parts.collect { |x| x.text }.to_s
      
      # Create message from the resulting text
      create_at_message source, destination, data_coding, text

      # Delete stored information
      SmppMessagePart.delete_all conditions
    else
      # Just save the part
      SmppMessagePart.create(
      :channel_id => @channel.id,
      :reference_number => ref,
      :part_count => total,
      :part_number => partn,
      :text => text
      )
    end
  end
  
  private
  
  def encoding_endianized(encoding)
    encoding == 'ucs-2' ? ucs2_endianized : encoding
  end
  
  def ucs2_endianized
    @channel.configuration[:endianness] == 'little' ? 'ucs-2le' : 'ucs-2be'
  end
  
  def is_hex(msg)
    msg =~ /[0-9a-fA-F]{4}+/
  end
  
  def hex_to_bytes(msg)
    msg.scan(/../).map{|x| x.to_i(16).chr}.join
  end
  
  def bytes_to_int(bytes)
    value = 0
    bytes.bytes.each do |x|
      value = (value << 8) + x
    end
    return value
  end
  
end
