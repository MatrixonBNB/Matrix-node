class FacetBlock < ApplicationRecord
  include Memery
  
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :eth_block_hash, optional: true
  has_many :facet_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :facet_transaction_receipts, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  
  GAS_LIMIT = 300e6.to_i
  attr_accessor :in_memory_txs
  
  def self.from_eth_block(eth_block, block_number)
    FacetBlock.new(
      eth_block_hash: eth_block.block_hash,
      eth_block_number: eth_block.number,
      parent_beacon_block_root: eth_block.parent_beacon_block_root,
      number: block_number,
      timestamp: eth_block.timestamp,
      prev_randao: eth_block.mix_hash
    )
  end
  
  def self.from_rpc_result(res)
    fb = new
    fb.from_rpc_response(res)
    fb
  end
  
  def from_rpc_response(resp)
    assign_attributes(
      number: (resp['blockNumber'] || resp['number']).to_i(16),
      block_hash: (resp['hash'] || resp['blockHash']),
      parent_hash: resp['parentHash'],
      state_root: resp['stateRoot'],
      receipts_root: resp['receiptsRoot'],
      logs_bloom: resp['logsBloom'],
      gas_limit: resp['gasLimit'].to_i(16),
      gas_used: resp['gasUsed'].to_i(16),
      timestamp: resp['timestamp'].to_i(16),
      base_fee_per_gas: resp['baseFeePerGas'].to_i(16),
      prev_randao: resp['prevRandao'] || resp['mixHash'],
      extra_data: resp['extraData'],
      in_memory_txs: resp['transactions'],
      # transactions_root: resp['transactionsRoot'],
    )
  rescue => e
    binding.irb
    raise
  end
  
  def calculated_base_fee_per_gas
    return base_fee_per_gas if base_fee_per_gas
    
    TransactionHelper.calculate_next_base_fee(number - 1)
  end
  memoize :calculated_base_fee_per_gas
end
