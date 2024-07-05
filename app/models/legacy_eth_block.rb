class LegacyEthBlock < ApplicationRecord
  self.table_name = "eth_blocks"
  
  has_many :ethscriptions, foreign_key: :block_number, primary_key: :block_number, inverse_of: :eth_block, autosave: false
  has_many :transaction_receipts, foreign_key: :block_number, primary_key: :block_number, inverse_of: :eth_block, autosave: false, class_name: "LegacyFacetTransactionReceipt"

end
