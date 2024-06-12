class Array
  # Pack an array of uint8 values into a byte string
  def uint8_array_to_bytes
    self.pack('C*')
  end

  # Unpack a byte string into an array of uint8 values
  def self.uint8_array_from_bytes(byte_string)
    byte_string.unpack('C*')
  end
end

class String
  # Convert a byte string to an array of uint8 values
  def bytes_to_uint8_array
    self.unpack('C*')
  end
  
  def bytes_to_hex
    "0x" + self.unpack1('H*')
  end
  
  def hex_to_bytes
    [self.sub(/\A0x/, '')].pack('H*')
  end
end
