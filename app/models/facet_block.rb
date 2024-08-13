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
  
  def self.check_hashes(batch_size: 1000)
    offset = 0

    loop do
      # Fetch block hashes from the other database in batches
      other_db_hashes = OtherFacetBlock.order(:number).limit(batch_size).offset(offset).pluck(:block_hash)
      break if other_db_hashes.empty?

      # Fetch block hashes from the current database in the same batch
      current_db_hashes = FacetBlock.order(:number).limit(batch_size).offset(offset).pluck(:block_hash)
      break if current_db_hashes.empty?

      # Compare the hashes
      return unless compare_hashes(current_db_hashes, other_db_hashes, offset)

      offset += batch_size
    end
  end

  def self.compare_hashes(current_db_hashes, other_db_hashes, offset)
    current_db_hashes.each_with_index do |hash, index|
      if hash != other_db_hashes[index]
        puts "Mismatch found at index #{index + offset}: #{hash} != #{other_db_hashes[index]}"
        compare_transactions(hash, other_db_hashes[index])
        return false
      end
    end
    true
  end

  def self.compare_transactions(current_block_hash, other_block_hash)
    current_txs = FacetTransaction.where(block_hash: current_block_hash).order(:transaction_index).pluck(:tx_hash)
    other_txs = OtherFacetTransaction.where(block_hash: other_block_hash).order(:transaction_index).pluck(:tx_hash)

    current_txs.each_with_index do |tx_hash, index|
      if tx_hash != other_txs[index]
        puts "Transaction mismatch found at index #{index}: #{tx_hash} != #{other_txs[index]}"
      end
    end
  end
end
