module L1AttributesTxCalldata
  extend self
  
  FUNCTION_SELECTOR = Eth::Util.keccak256('setL1BlockValuesEcotone()').first(4)
  
  def build(
    timestamp:,
    number:,
    base_fee:,
    blob_base_fee: 1,
    hash:,
    sequence_number:,
    fct_mint_rate:,
    fct_minted_in_rate_adjustment_period:
  )
    base_fee_scalar = 0
    blob_base_fee_scalar = 1
    batcher_hash = "\x00" * 32
    
    hash = hash.hex_to_bin
    
    unless hash.length == 32
      raise "Invalid hash length"
    end
    
    packed_data = [
      FUNCTION_SELECTOR,
      base_fee_scalar.zpad(4),
      blob_base_fee_scalar.zpad(4),
      sequence_number.zpad(8),
      timestamp.zpad(8),
      number.zpad(8),
      base_fee.zpad(32),
      blob_base_fee.zpad(32),
      hash,
      batcher_hash,
      fct_mint_rate.zpad(32),
      fct_minted_in_rate_adjustment_period.zpad(32)
    ].join
    
    packed_data.bytes_to_hex
  end
  
  def decode(calldata)
    data = calldata.hex_to_bytes
  
    # Remove the function selector
    data = data[4..-1]
    
    # Unpack the data
    base_fee_scalar = data[0...4].unpack1('N')
    blob_base_fee_scalar = data[4...8].unpack1('N')
    sequence_number = data[8...16].unpack1('Q>')
    timestamp = data[16...24].unpack1('Q>')
    number = data[24...32].unpack1('Q>')
    base_fee = data[32...64].unpack1('H*').to_i(16)
    blob_base_fee = data[64...96].unpack1('H*').to_i(16)
    hash = data[96...128].unpack1('H*')
    batcher_hash = data[128...160].unpack1('H*')
    fct_mint_rate = data[160...192].unpack1('H*').to_i(16)
    fct_minted_in_rate_adjustment_period = data[192...224].unpack1('H*').to_i(16)
    
    {
      timestamp: timestamp,
      number: number,
      base_fee: base_fee,
      blob_base_fee: blob_base_fee,
      hash: "0x#{hash}",
      batcher_hash: "0x#{batcher_hash}",
      sequence_number: sequence_number,
      blob_base_fee_scalar: blob_base_fee_scalar,
      base_fee_scalar: base_fee_scalar,
      fct_mint_rate: fct_mint_rate,
      fct_minted_in_rate_adjustment_period: fct_minted_in_rate_adjustment_period
    }.with_indifferent_access
  end
end
