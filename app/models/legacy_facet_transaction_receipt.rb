class LegacyFacetTransactionReceipt < ApplicationRecord
  self.table_name = "transaction_receipts"

  belongs_to :legacy_facet_transaction, primary_key: :transaction_hash, foreign_key: :transaction_hash
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, inverse_of: :transaction_receipts, optional: true, autosave: false, class_name: "LegacyEthBlock"
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  def sample_upgrade
    s = EthBlock.reading{LegacyFacetTransactionReceipt.where(function: 'upgradeAndCall').first}
    
    hsh = s['args']['newHash']
    calldata = s['args']['migrationCalldata']
    to = s.to_address
    
    args = Ethscription.convert_args(contract_name, data['function'], data['args'])

  end
end
