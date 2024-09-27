class EthBlock < ApplicationRecord
  has_many :eth_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :eth_calls, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_one :facet_block, primary_key: :block_hash, foreign_key: :eth_block_hash, dependent: :destroy
  
  def self.from_rpc_result(block_result)
    EthBlock.new(
      number: block_result['number'].to_i(16),
      block_hash: block_result['hash'],
      base_fee_per_gas: block_result['baseFeePerGas'].to_i(16),
      parent_beacon_block_root: block_result['parentBeaconBlockRoot'],
      mix_hash: block_result['mixHash'],
      parent_hash: block_result['parentHash'],
      timestamp: block_result['timestamp'].to_i(16)
    )
  end
end
