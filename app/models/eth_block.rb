class EthBlock < T::Struct
  include AttrAssignable

  # Primary schema fields
  prop :number, Integer
  prop :block_hash, Hash32
  prop :base_fee_per_gas, Integer
  prop :parent_beacon_block_root, Hash32
  prop :mix_hash, Hash32
  prop :parent_hash, Hash32
  prop :timestamp, Integer

  # Association-like field
  prop :facet_block, T.nilable(FacetBlock)
  
  sig { params(block_result: T.untyped).returns(EthBlock) }
  def self.from_rpc_result(block_result)
    EthBlock.new(
      number: block_result['number'].to_i(16),
      block_hash: Hash32.from_hex(block_result['hash']),
      base_fee_per_gas: block_result['baseFeePerGas'].to_i(16),
      parent_beacon_block_root: Hash32.from_hex(block_result['parentBeaconBlockRoot']),
      mix_hash: Hash32.from_hex(block_result['mixHash']),
      parent_hash: Hash32.from_hex(block_result['parentHash']),
      timestamp: block_result['timestamp'].to_i(16)
    )
  end
end
