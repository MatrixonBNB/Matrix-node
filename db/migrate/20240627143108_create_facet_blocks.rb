class CreateFacetBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :facet_blocks do |t|
      t.bigint :number, null: false
      t.string :block_hash, null: false
      t.string :eth_block_hash, null: false
      t.bigint :base_fee_per_gas, null: false
      t.string :extra_data, null: false
      t.bigint :gas_limit, null: false
      t.bigint :gas_used, null: false
      t.text :logs_bloom, null: false
      t.string :parent_beacon_block_root, null: false
      t.string :parent_hash, null: false
      t.string :receipts_root, null: false
      t.integer :size, null: false
      t.string :state_root, null: false
      t.integer :timestamp, null: false
      t.string :transactions_root, null: false
      t.string :prev_randao, null: false

      t.timestamps
    end

    add_index :facet_blocks, :number, unique: true
    add_index :facet_blocks, :block_hash, unique: true
    add_index :facet_blocks, :eth_block_hash, unique: true

    add_foreign_key :facet_blocks, :eth_blocks, column: :eth_block_hash, primary_key: :block_hash, on_delete: :cascade
  end
end
