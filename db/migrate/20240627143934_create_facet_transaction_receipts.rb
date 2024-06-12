class CreateFacetTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :facet_transaction_receipts do |t|
      t.string :transaction_hash, null: false
      t.string :block_hash, null: false
      t.integer :block_number, null: false
      t.string :contract_address
      t.bigint :cumulative_gas_used, null: false
      t.string :deposit_nonce, null: false
      t.string :deposit_receipt_version, null: false
      t.bigint :effective_gas_price, null: false
      t.string :from_address, null: false
      t.bigint :gas_used, null: false
      t.jsonb :logs, null: false, default: []
      t.text :logs_bloom, null: false
      t.integer :status, null: false
      t.string :to_address
      t.integer :transaction_index, null: false
      t.string :tx_type, null: false

      t.timestamps
    end

    add_index :facet_transaction_receipts, :transaction_hash, unique: true
    add_index :facet_transaction_receipts, :block_hash
    add_index :facet_transaction_receipts, :block_number
    add_foreign_key :facet_transaction_receipts, :facet_transactions, column: :transaction_hash, primary_key: :tx_hash, on_delete: :cascade
    add_foreign_key :facet_transaction_receipts, :facet_blocks, column: :block_hash, primary_key: :block_hash, on_delete: :cascade
  end
end
