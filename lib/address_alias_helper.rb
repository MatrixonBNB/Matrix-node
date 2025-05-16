module AddressAliasHelper
  extend self
  class InvalidAddress < StandardError; end
  
  OFFSET = 0x1111000000000000000000000000000000001111
  
  sig { params(l1_address: Address20).returns(Address20) }
  def apply_l1_to_l2_alias(l1_address)
    # Convert the L1 address to a 160-bit integer
    l1_address_int = l1_address.to_hex.to_i(16)
    
    # Add the offset (unchecked, no overflow handling needed)
    l2_address_int = (l1_address_int + OFFSET) % (2**160)
  
    # Convert the result back to a hex string representing a 20-byte Ethereum address
    l2_address_hex = "0x" + l2_address_int.to_s(16).rjust(40, '0') # Ensure it's padded to 20 bytes
  
    Address20.from_hex(l2_address_hex)
  end
  
  sig { params(l2_address: Address20).returns(Address20) }
  def undo_l1_to_l2_alias(l2_address)
    l2_address_int = l2_address.to_hex.to_i(16)
    
    # Convert the L2 address to a 160-bit integer
    l2_address_int = l2_address.to_i(16)
    
    # Subtract the offset (unchecked, using modular arithmetic for 160-bit unsigned integers)
    l1_address_int = (l2_address_int - OFFSET) % (2**160)
  
    # Convert the result back to a hex string representing a 20-byte Ethereum address
    l1_address_hex = "0x" + l1_address_int.to_s(16).rjust(40, '0') # Ensure it's padded to 20 bytes
  
    Address20.from_hex(l1_address_hex)
  end
end
