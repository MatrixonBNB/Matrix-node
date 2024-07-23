class FacetBlock < ApplicationRecord
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :eth_block_hash
  has_many :facet_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :delete_all
  has_many :facet_transaction_receipts, primary_key: :block_hash, foreign_key: :block_hash, dependent: :delete_all
  
  def self.from_eth_block(eth_block, block_number, timestamp: nil)
    FacetBlock.new(
      eth_block_hash: eth_block.block_hash,
      eth_block_number: eth_block.number,
      parent_beacon_block_root: eth_block.parent_beacon_block_root,
      number: block_number,
      timestamp: timestamp || eth_block.timestamp,
      prev_randao: FacetBlock.calculate_prev_randao(eth_block.block_hash)
    )
  end
  
  def from_rpc_response(resp)
    assign_attributes(
      number: resp['number'].to_i(16),
      block_hash: resp['hash'],
      parent_hash: resp['parentHash'],
      state_root: resp['stateRoot'],
      receipts_root: resp['receiptsRoot'],
      logs_bloom: resp['logsBloom'],
      gas_limit: resp['gasLimit'].to_i(16),
      gas_used: resp['gasUsed'].to_i(16),
      timestamp: resp['timestamp'].to_i(16),
      base_fee_per_gas: resp['baseFeePerGas'].to_i(16),
      prev_randao: FacetBlock.calculate_prev_randao(resp['hash']),
      extra_data: resp['extraData'],
      size: resp['size'].to_i(16),
      transactions_root: resp['transactionsRoot'],
    )
  end
  
  def self.calculate_prev_randao(block_hash)
    Eth::Util.keccak256(block_hash.hex_to_bytes + 'prevRandao').bytes_to_hex
  end
end
