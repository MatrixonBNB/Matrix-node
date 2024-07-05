class LegacyFacetTransaction < ApplicationRecord
  self.table_name = "contract_transactions"
  
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :transaction_hash, optional: true
  has_one :transaction_receipt, foreign_key: :transaction_hash, primary_key: :transaction_hash, inverse_of: :legacy_facet_transaction, class_name: "LegacyFacetTransactionReceipt"
end
