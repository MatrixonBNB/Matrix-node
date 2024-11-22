class CreateFacetTransactionReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :facet_transaction_receipts do |t|
      t.string :transaction_hash, null: false
      t.string :block_hash, null: false
      t.integer :block_number, null: false
      t.string :contract_address
      t.column :legacy_contract_address_map, :jsonb, null: false, default: {}
      t.bigint :cumulative_gas_used, null: false
      t.string :deposit_nonce, null: false
      t.string :deposit_receipt_version, null: false
      t.bigint :effective_gas_price, null: false
      t.string :from_address, null: false
      t.bigint :gas_used, null: false
      t.column :logs, :jsonb, null: false, default: []
      t.text :logs_bloom, null: false
      t.integer :status, null: false
      t.string :to_address
      t.integer :transaction_index, null: false
      t.string :tx_type, null: false

      if pg_adapter?
        t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
        t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"
        t.check_constraint "contract_address ~ '^0x[a-f0-9]{40}$'"
      end
      
      t.timestamps
      
      t.index :legacy_contract_address_map, using: :gin
      t.index :transaction_hash, unique: true
      t.index :block_hash
      t.index :block_number
      t.index :transaction_index
      t.index [:block_number, :transaction_index]
    end

    return unless pg_adapter?

    add_foreign_key :facet_transaction_receipts, :facet_transactions, column: :transaction_hash, primary_key: :tx_hash, on_delete: :cascade
    add_foreign_key :facet_transaction_receipts, :facet_blocks, column: :block_hash, primary_key: :block_hash, on_delete: :cascade
  end
end
