class FacetBlock < ApplicationRecord
  include Memery
  
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :eth_block_hash, optional: true
  has_many :facet_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :facet_transaction_receipts, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  
  GAS_LIMIT = 300e6.to_i
  attr_accessor :in_memory_txs
  
  def self.genesis_block
    ENV.fetch("START_BLOCK").to_i - 1
  end
  
  def self.v2_fork_block
    ENV.fetch("V2_FORK_BLOCK").to_i
  end
  
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
  
  def self.compare_geth_instances(geth_rpc_url, other_rpc_url)
    geth_client = GethClient.new(geth_rpc_url)
    other_client = GethClient.new(other_rpc_url)

    # Fetch the latest block number from the Geth instance
    latest_geth_block = geth_client.call("eth_getBlockByNumber", ["latest", false])
    latest_geth_block_number = latest_geth_block['number'].to_i(16)
  
    # Fetch the latest block number from the other database
    latest_other_block = other_client.call("eth_getBlockByNumber", ["latest", false])
    latest_other_block_number = latest_other_block['number'].to_i(16)
  
    # Determine the smaller of the two block numbers
    max_block_number = [latest_geth_block_number, latest_other_block_number].min
  
    # Check if the latest common block hash matches
    geth_block = geth_client.call("eth_getBlockByNumber", ["0x" + max_block_number.to_s(16), false])
    geth_hash = geth_block['hash']
    other_block = other_client.call("eth_getBlockByNumber", ["0x" + max_block_number.to_s(16), false])
    other_hash = other_block['hash']
  
    if geth_hash == other_hash
      puts "Latest common block (#{max_block_number}) hashes match. No discrepancies found."
      return true
    else
      puts "Mismatch found at the latest common block (#{max_block_number}): #{other_hash} != #{geth_hash}"
      puts "Searching for the point of divergence..."
    end
  
    find_divergence_point(geth_client, other_client, 0, max_block_number)
  end
  
  def self.find_divergence_point(geth_client, other_client, start_block, end_block)
    while start_block < end_block
      mid_block = (start_block + end_block) / 2
  
      geth_block = geth_client.call("eth_getBlockByNumber", ["0x" + mid_block.to_s(16), false])
      geth_hash = geth_block['hash']
      other_block = other_client.call("eth_getBlockByNumber", ["0x" + mid_block.to_s(16), false])
      other_hash = other_block['hash']
  
      if geth_hash == other_hash
        # Hashes match, divergence point is after this block
        start_block = mid_block + 1
      else
        # Hashes don't match, divergence point is this block or before
        end_block = mid_block
      end
    end
  
    # At this point, start_block is the first block where hashes differ
    puts "Divergence found at block #{start_block}"
    compare_transactions(geth_client, other_client, start_block, other_hash, geth_hash)
    return start_block
  end

  def self.compare_transactions(geth_client, other_client, block_number, other_block_hash, geth_block_hash)
    # Fetch transactions from the other client
    other_block = other_client.call("eth_getBlockByNumber", ["0x" + block_number.to_s(16), true])
    other_txs = other_block['transactions'].map { |tx| tx['hash'] }
  
    # Fetch transactions from the Geth instance
    geth_block = geth_client.call("eth_getBlockByNumber", ["0x" + block_number.to_s(16), true])
    geth_txs = geth_block['transactions'].map { |tx| tx['hash'] }

    other_txs.each_with_index do |tx_hash, index|
      if tx_hash != geth_txs[index]
        puts "Transaction mismatch found at index #{index} in block number #{block_number}: #{tx_hash} != #{geth_txs[index]}"
        ap geth_client.call("eth_getTransactionByHash", [geth_txs[index]])
      end
    end
  end
end
