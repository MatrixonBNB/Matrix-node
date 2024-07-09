class CreateFacetTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :facet_transactions do |t|
      t.string :eth_transaction_hash, null: false
      t.integer :eth_call_index, null: false
      t.string :block_hash, null: false
      t.bigint :block_number, null: false
      t.string :deposit_receipt_version, null: false
      t.string :from_address, null: false
      t.bigint :gas, null: false
      t.bigint :gas_limit, null: false
      t.numeric :gas_price, precision: 78, scale: 0#, null: false
      t.string :tx_hash, null: false
      t.text :input, null: false
      # t.integer :nonce, null: false
      # t.string :r, null: false
      # t.string :s, null: false
      t.string :source_hash, null: false
      t.string :to_address
      t.integer :transaction_index, null: false
      t.string :tx_type, null: false
      # t.integer :y_parity, null: false
      t.numeric :mint, precision: 78, scale: 0, null: false
      t.numeric :value, precision: 78, scale: 0, null: false
      t.numeric :max_fee_per_gas, precision: 78, scale: 0#, null: false
      
      t.check_constraint "source_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "tx_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "eth_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"
      
      t.timestamps
    end

    add_index :facet_transactions, :source_hash, unique: true
    add_index :facet_transactions, :block_hash
    add_index :facet_transactions, [:block_hash, :eth_call_index], unique: true
    add_index :facet_transactions, :block_number
    add_index :facet_transactions, :tx_hash, unique: true
    add_index :facet_transactions, :eth_transaction_hash

    add_foreign_key :facet_transactions, :eth_transactions, column: :eth_transaction_hash, primary_key: :tx_hash, on_delete: :cascade
    add_foreign_key :facet_transactions, :facet_blocks, column: :block_hash, primary_key: :block_hash, on_delete: :cascade
  end
end
