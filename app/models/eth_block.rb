class EthBlock < ApplicationRecord
  has_many :eth_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :delete_all
  has_many :eth_calls, primary_key: :block_hash, foreign_key: :block_hash, dependent: :delete_all
  has_many :facet_blocks, primary_key: :block_hash, foreign_key: :eth_block_hash, dependent: :delete_all
  
  def self.from_rpc_result(res)
    block_result = res['result']
    
    unless block_result
      raise "No block result"
    end
    
    EthBlock.new(
      number: block_result['number'].to_i(16),
      block_hash: block_result['hash'],
      logs_bloom: block_result['logsBloom'],
      total_difficulty: block_result['totalDifficulty'].to_i(16),
      receipts_root: block_result['receiptsRoot'],
      extra_data: block_result['extraData'],
      withdrawals_root: block_result['withdrawalsRoot'],
      base_fee_per_gas: block_result['baseFeePerGas']&.to_i(16),
      nonce: block_result['nonce'],
      miner: block_result['miner'],
      excess_blob_gas: block_result['excessBlobGas']&.to_i(16),
      difficulty: block_result['difficulty'].to_i(16),
      gas_limit: block_result['gasLimit'].to_i(16),
      gas_used: block_result['gasUsed'].to_i(16),
      parent_beacon_block_root: block_result['parentBeaconBlockRoot'] || block_result['parentHash'],
      size: block_result['size'].to_i(16),
      transactions_root: block_result['transactionsRoot'],
      state_root: block_result['stateRoot'],
      mix_hash: block_result['mixHash'],
      parent_hash: block_result['parentHash'],
      blob_gas_used: block_result['blobGasUsed']&.to_i(16),
      timestamp: block_result['timestamp'].to_i(16)
    )
  end
  
  def self.from_legacy_eth_block(legacy_block)
    EthBlock.new(
      number: legacy_block.block_number,
      block_hash: legacy_block.blockhash,
      parent_hash: legacy_block.parent_blockhash,
      timestamp: legacy_block.timestamp,
      parent_beacon_block_root: legacy_block.parent_blockhash,
    )
  end
end
