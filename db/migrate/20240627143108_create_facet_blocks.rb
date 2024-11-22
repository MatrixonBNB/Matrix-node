class CreateFacetBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :facet_blocks do |t|
      t.bigint :number, null: false
      t.string :block_hash, null: false
      t.string :eth_block_hash, null: false
      t.integer :eth_block_number, null: false
      t.bigint :base_fee_per_gas, null: false
      t.string :extra_data, null: false
      t.bigint :gas_limit, null: false
      t.bigint :gas_used, null: false
      t.text :logs_bloom, null: false
      t.string :parent_beacon_block_root#, null: false
      t.string :parent_hash, null: false
      t.string :receipts_root, null: false
      t.integer :size#, null: false
      t.string :state_root, null: false
      t.bigint :timestamp, null: false
      t.string :transactions_root#, null: false
      t.string :prev_randao, null: false
      
      t.bigint :eth_block_timestamp
      t.bigint :eth_block_base_fee_per_gas
      t.integer :sequence_number, null: false
      
      t.bigint :fct_mint_rate
      t.numeric :fct_mint_period_l1_data_gas, precision: 78, scale: 0
      
      if pg_adapter?
        t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "parent_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "prev_randao ~ '^0x[a-f0-9]{64}$'"
      end

      t.timestamps
    end

    return unless pg_adapter?

    add_index :facet_blocks, :number, unique: true
    add_index :facet_blocks, :block_hash, unique: true

    add_foreign_key :facet_blocks, :eth_blocks, column: :eth_block_hash, primary_key: :block_hash, on_delete: :cascade
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
        CREATE OR REPLACE FUNCTION check_facet_block_order()
        RETURNS TRIGGER AS $$
        BEGIN
          IF (SELECT MAX(number) FROM facet_blocks) IS NOT NULL AND (NEW.number <> (SELECT MAX(number) + 1 FROM facet_blocks) OR NEW.parent_hash <> (SELECT block_hash FROM facet_blocks WHERE number = NEW.number - 1)) THEN
            RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block. Provided: new number = %, expected number = %, new parent hash = %, expected parent hash = %',
            NEW.number, (SELECT MAX(number) + 1 FROM facet_blocks), NEW.parent_hash, (SELECT block_hash FROM facet_blocks WHERE number = NEW.number - 1);
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        
          CREATE TRIGGER trigger_check_facet_block_order
          BEFORE INSERT ON facet_blocks
          FOR EACH ROW EXECUTE FUNCTION check_facet_block_order();
        SQL
      end
    end
  end
end
