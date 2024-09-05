class AddFacetTransactionReceiptsIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :facet_transaction_receipts, :transaction_index
  end
end
