module L1AttributesTxCalldata
  extend self
  
  FUNCTION_SELECTOR = Eth::Util.keccak256('setL1BlockValuesEcotone()').bytes_to_hex[0...10]
  
  def build(
    timestamp:,
    number:,
    base_fee:,
    blob_base_fee: 1,
    hash:,
    batcher_hash: "0x" + "0" * 40
  )
    base_fee_scalar = 0
    blob_base_fee_scalar = 1
    sequence_number = 0
    
    # Pack the first 3 parameters into a single uint256
    packed_scalars_and_sequence = (
      (sequence_number << 64) |
      (blob_base_fee_scalar << 32) |
      base_fee_scalar
    )
  
    # Pack number and timestamp into a single uint256
    packed_number_and_timestamp = (number << 64) | timestamp
  
    # Encode the parameters using Eth::Abi.encode
    encoded_params = Eth::Abi.encode(
      ['uint256', 'uint256', 'uint256', 'uint256', 'bytes32', 'bytes32'],
      [
        packed_scalars_and_sequence,
        packed_number_and_timestamp,
        base_fee,
        blob_base_fee,
        Eth::Util.hex_to_bin(hash),
        Eth::Util.hex_to_bin(batcher_hash)
      ]
    )
  
    # Combine function selector and encoded parameters
    FUNCTION_SELECTOR + encoded_params.bytes_to_unprefixed_hex
  end
end
