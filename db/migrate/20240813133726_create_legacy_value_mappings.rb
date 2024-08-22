class CreateLegacyValueMappings < ActiveRecord::Migration[7.1]
  def up
    create_table :legacy_value_mappings do |t|
      t.string :legacy_value, null: false
      t.string :new_value, null: false
      
      t.index :legacy_value, unique: true
      
      t.check_constraint "(legacy_value ~ '^0x[a-f0-9]{64}$' AND new_value ~ '^0x[a-f0-9]{64}$') OR (legacy_value ~ '^0x[a-f0-9]{40}$' AND new_value ~ '^0x[a-f0-9]{40}$')", name: "legacy_and_new_value_pattern_check"
      
      t.timestamps
    end
    
    execute <<-SQL
      CREATE OR REPLACE FUNCTION check_legacy_value_conflict()
      RETURNS TRIGGER AS $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM legacy_value_mappings
          WHERE legacy_value = NEW.legacy_value
            AND new_value <> NEW.new_value
        ) THEN
          RAISE EXCEPTION 'Conflict: legacy_value % is already mapped to a different new_value', NEW.legacy_value;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trigger_check_legacy_value_conflict
      BEFORE INSERT OR UPDATE ON legacy_value_mappings
      FOR EACH ROW EXECUTE FUNCTION check_legacy_value_conflict();
    SQL
  end
  
  def down
    drop_table :legacy_value_mappings
  end
end
