class FacetTransaction < ApplicationRecord
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
  has_one :facet_transaction_receipt, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  belongs_to :eth_transaction, primary_key: :tx_hash, foreign_key: :eth_transaction_hash
end
