class RemoveNotNullConstraintFromFacetTransactions < ActiveRecord::Migration[6.1]
  def up
    change_column_null :facet_transactions, :eth_transaction_hash, true
    change_column_null :facet_transactions, :eth_call_index, true
  end

  def down
    # change_column_null :facet_transactions, :eth_transaction_hash, false
    # change_column_null :facet_transactions, :eth_call_index, false
  end
end
