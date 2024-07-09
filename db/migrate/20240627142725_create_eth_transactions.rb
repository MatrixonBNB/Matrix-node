class CreateEthTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_transactions do |t|
      t.string :block_hash, null: false
      t.bigint :block_number, null: false
      t.string :tx_hash, null: false
      t.integer :y_parity#, null: false
      t.jsonb :access_list#, null: false, default: []
      t.integer :transaction_index#, null: false
      t.integer :tx_type#, null: false
      t.integer :nonce#, null: false
      t.text :input#, null: false
      t.string :r#, null: false
      t.string :s#, null: false
      t.integer :chain_id#, null: false
      t.integer :v#, null: false
      t.bigint :gas#, null: false
      t.numeric :max_priority_fee_per_gas, precision: 78, scale: 0#, null: false
      t.string :from_address#, null: false
      t.string :to_address#, null: false
      t.numeric :max_fee_per_gas, precision: 78, scale: 0#, null: false
      t.numeric :value, precision: 78, scale: 0, null: false
      t.numeric :gas_price, precision: 78, scale: 0#, null: false
      
      t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "tx_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"

      t.timestamps
    end

    add_foreign_key :eth_transactions, :eth_blocks, column: :block_hash, primary_key: :block_hash, on_delete: :cascade
    add_index :eth_transactions, :block_hash
    add_index :eth_transactions, :block_number
    add_index :eth_transactions, :tx_hash, unique: true
  end
end
