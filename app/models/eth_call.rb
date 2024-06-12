class EthCall < ApplicationRecord
  validates :block_hash, :transaction_hash, :from_address, :gas, :gas_used, presence: true
  
  belongs_to :eth_block, foreign_key: :block_hash, primary_key: :block_hash
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash
end
