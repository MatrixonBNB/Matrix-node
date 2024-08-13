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
  
  def decode(calldata)
    # Remove the function selector
    encoded_params = calldata[FUNCTION_SELECTOR.length..-1]
    
    # Decode the parameters using Eth::Abi.decode
    decoded_params = Eth::Abi.decode(
      ['uint256', 'uint256', 'uint256', 'uint256', 'bytes32', 'bytes32'],
      Eth::Util.hex_to_bin(encoded_params)
    )
    
    packed_scalars_and_sequence, packed_number_and_timestamp, base_fee, blob_base_fee, hash, batcher_hash = decoded_params
    
    # Unpack the first 3 parameters from the first uint256
    sequence_number = (packed_scalars_and_sequence >> 64) & 0xFFFFFFFFFFFFFFFF
    blob_base_fee_scalar = (packed_scalars_and_sequence >> 32) & 0xFFFFFFFF
    base_fee_scalar = packed_scalars_and_sequence & 0xFFFFFFFF
    
    # Unpack number and timestamp from the second uint256
    number = (packed_number_and_timestamp >> 64) & 0xFFFFFFFFFFFFFFFF
    timestamp = packed_number_and_timestamp & 0xFFFFFFFFFFFFFFFF
    
    {
      timestamp: timestamp,
      number: number,
      base_fee: base_fee,
      blob_base_fee: blob_base_fee,
      hash: Eth::Util.bin_to_hex(hash),
      batcher_hash: Eth::Util.bin_to_hex(batcher_hash),
      sequence_number: sequence_number,
      blob_base_fee_scalar: blob_base_fee_scalar,
      base_fee_scalar: base_fee_scalar
    }.with_indifferent_access
  end
end
