class EthTransaction < ApplicationRecord
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :block_hash
  has_many :eth_calls, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  has_many :facet_transactions, -> { order(eth_call_index: :asc) },
    primary_key: :tx_hash, foreign_key: :eth_transaction_hash, dependent: :destroy
end
