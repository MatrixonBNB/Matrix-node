class EthTransaction < ApplicationRecord
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :block_hash
  has_many :eth_calls, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  has_one :ethscription, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  has_many :facet_transactions, -> { order(eth_call_index: :asc) },
    primary_key: :tx_hash, foreign_key: :eth_transaction_hash, dependent: :destroy
    
    
  def self.from_rpc_result(block_by_number_response)
    block_result = block_by_number_response['result']
    
    block_hash = block_result['hash']
    block_number = block_result['number'].to_i(16)
    
    block_result['transactions'].map do |tx|
      EthTransaction.new(
        block_hash: block_hash,
        block_number: block_number,
        tx_hash: tx['hash'],
        y_parity: tx['yParity']&.to_i(16),
        access_list: tx['accessList'],
        transaction_index: tx['transactionIndex'].to_i(16),
        tx_type: tx['type'].to_i(16),
        nonce: tx['nonce'].to_i(16),
        input: tx['input'],
        r: tx['r'],
        s: tx['s'],
        chain_id: tx['chainId']&.to_i(16),
        v: tx['v'].to_i(16),
        gas: tx['gas'].to_i(16),
        max_priority_fee_per_gas: tx['maxPriorityFeePerGas']&.to_i(16),
        from_address: tx['from'],
        to_address: tx['to'],
        max_fee_per_gas: tx['maxFeePerGas']&.to_i(16),
        value: tx['value'].to_i(16),
        gas_price: tx['gasPrice'].to_i(16)
      )
    end
  end
end
