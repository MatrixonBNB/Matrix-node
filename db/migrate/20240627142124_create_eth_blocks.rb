class CreateEthBlocks < ActiveRecord::Migration[7.1]
  def change
    create_table :eth_blocks do |t|
      t.bigint :number, null: false
      t.string :block_hash, null: false
      t.bigint :base_fee_per_gas
      t.string :parent_beacon_block_root
      t.string :mix_hash
      t.string :parent_hash, null: false
      t.bigint :timestamp, null: false
      
      t.datetime :imported_at
      
      if pg_adapter?
        t.check_constraint "mix_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "block_hash ~ '^0x[a-f0-9]{64}$'"
        t.check_constraint "parent_hash ~ '^0x[a-f0-9]{64}$'"      
        t.check_constraint "parent_beacon_block_root ~ '^0x[a-f0-9]{64}$'"      
      end

      t.timestamps
    end
    
    return unless pg_adapter?
    
    add_index :eth_blocks, :number, unique: true
    add_index :eth_blocks, :block_hash, unique: true
    
    reversible do |dir|
      dir.up do
        execute <<-SQL
        CREATE OR REPLACE FUNCTION check_eth_block_order()
        RETURNS TRIGGER AS $$
        BEGIN
          IF (SELECT MAX(number) FROM eth_blocks) IS NOT NULL AND (NEW.number <> (SELECT MAX(number) + 1 FROM eth_blocks) OR NEW.parent_hash <> (SELECT block_hash FROM eth_blocks WHERE number = NEW.number - 1)) THEN
            RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block. Provided: new number = %, expected number = %, new parent hash = %, expected parent hash = %',
            NEW.number, (SELECT MAX(number) + 1 FROM eth_blocks), NEW.parent_hash, (SELECT block_hash FROM eth_blocks WHERE number = NEW.number - 1);
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        
          CREATE TRIGGER trigger_check_eth_block_order
          BEFORE INSERT ON eth_blocks
          FOR EACH ROW EXECUTE FUNCTION check_eth_block_order();
        SQL
      end
    end
  end
end
