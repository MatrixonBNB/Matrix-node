class FacetTransactionReceipt < ApplicationRecord
  belongs_to :facet_transaction, primary_key: :tx_hash, foreign_key: :transaction_hash
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
end
