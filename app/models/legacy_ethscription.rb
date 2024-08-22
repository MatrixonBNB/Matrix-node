class LegacyEthscription < ApplicationRecord
  self.table_name = "ethscriptions"
  
  include LegacyModel
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true, autosave: false
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash, optional: true, autosave: false
  has_one :facet_transaction, primary_key: :transaction_hash, foreign_key: :tx_hash
  has_one :facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  has_one :legacy_facet_transaction, primary_key: :transaction_hash, foreign_key: :transaction_hash
  has_one :legacy_facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
end
