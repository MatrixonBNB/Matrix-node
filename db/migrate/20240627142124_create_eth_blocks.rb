class CreateEthBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_blocks do |t|
      t.bigint :number, null: false
      t.string :block_hash, null: false
      t.text :logs_bloom, null: false
      t.bigint :total_difficulty, null: false
      t.string :receipts_root, null: false
      t.string :extra_data, null: false
      t.string :withdrawals_root, null: false
      t.bigint :base_fee_per_gas, null: false
      t.string :nonce, null: false
      t.string :miner, null: false
      t.bigint :excess_blob_gas, null: false
      t.bigint :difficulty, null: false
      t.bigint :gas_limit, null: false
      t.bigint :gas_used, null: false
      t.string :parent_beacon_block_root, null: false
      t.integer :size, null: false
      t.string :transactions_root, null: false
      t.string :state_root, null: false
      t.string :mix_hash, null: false
      t.string :parent_hash, null: false
      t.bigint :blob_gas_used, null: false
      t.bigint :timestamp, null: false
      
      t.datetime :imported_at

      t.timestamps
    end
    
    add_index :eth_blocks, :number, unique: true
    add_index :eth_blocks, :block_hash, unique: true
  end
end
