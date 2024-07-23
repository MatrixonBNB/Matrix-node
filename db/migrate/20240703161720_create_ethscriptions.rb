class CreateEthscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :ethscriptions, force: :cascade do |t|
      t.string :transaction_hash, null: false
      t.bigint :block_number, null: false
      t.string :block_blockhash, null: false
      t.bigint :transaction_index, null: false
      t.string :creator, null: false
      t.string :initial_owner, null: false
      t.bigint :block_timestamp, null: false
      t.text :content_uri, null: false
      t.string :mimetype, null: false
      t.datetime :processed_at
      t.string :processing_state, null: false
      t.string :processing_error
      t.bigint :gas_price
      t.bigint :gas_used
      t.bigint :transaction_fee
      
      t.index [:block_number, :transaction_index], unique: true
      t.index :transaction_hash, unique: true
      t.index :processing_state
    
      t.check_constraint "block_blockhash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "creator ~ '^0x[a-f0-9]{40}$'"
      t.check_constraint "transaction_hash ~ '^0x[a-f0-9]{64}$'"
      t.check_constraint "initial_owner ~ '^0x[a-f0-9]{40}$'"
    
      t.check_constraint "processing_state IN ('pending', 'success', 'failure')"
      
      t.check_constraint "processing_state = 'pending' OR processed_at IS NOT NULL"
      
      # t.foreign_key :eth_blocks, column: :block_number, primary_key: :number, on_delete: :cascade
      
      t.timestamps
    end
    
    # add_foreign_key :ethscriptions, :eth_transactions, column: :transaction_hash, primary_key: :tx_hash, on_delete: :cascade
  end
end
