class CreateEthCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_calls do |t|
      t.integer :call_index, null: false
      t.integer :parent_call_index
      t.bigint :block_number, null: false
      t.string :block_hash, null: false
      t.string :transaction_hash, null: false
      t.string :from_address, null: false
      t.string :to_address
      t.bigint :gas
      t.bigint :gas_used
      t.text :input
      t.text :output
      t.numeric :value, precision: 78, scale: 0
      t.string :call_type
      t.string :error
      t.string :revert_reason
      
      t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "from_address ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "to_address ~ '^0x[a-f0-9]{40}$'"
      
      t.timestamps
    end

    add_index :eth_calls, :block_hash
    add_index :eth_calls, :block_number
    add_index :eth_calls, :transaction_hash
    add_index :eth_calls, [:block_hash, :call_index], unique: true
    add_index :eth_calls, [:block_hash, :parent_call_index]
    
    # add_foreign_key :eth_calls, :eth_blocks, column: :block_hash, primary_key: :block_hash, on_delete: :cascade
    # add_foreign_key :eth_calls, :eth_transactions, column: :transaction_hash, primary_key: :tx_hash, on_delete: :cascade
  end
end
