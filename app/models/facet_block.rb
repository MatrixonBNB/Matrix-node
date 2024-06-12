class FacetBlock < ApplicationRecord
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :eth_block_hash
  has_many :facet_transactions, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
  has_many :facet_transaction_receipts, primary_key: :block_hash, foreign_key: :block_hash, dependent: :destroy
end
