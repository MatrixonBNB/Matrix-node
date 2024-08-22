class ModifyCheckConstraintOnLegacyValueMappings < ActiveRecord::Migration[7.1]
  def up
    # Drop the existing check constraint
    execute <<-SQL
      ALTER TABLE legacy_value_mappings
      DROP CONSTRAINT legacy_and_new_value_pattern_check;
    SQL

    # Add the new check constraint only on new_value
    execute <<-SQL
      ALTER TABLE legacy_value_mappings
      ADD CONSTRAINT new_value_pattern_check
      CHECK (new_value ~ '^0x[a-f0-9]{64}$' OR new_value ~ '^0x[a-f0-9]{40}$');
    SQL
  end

  def down
    # Drop the new check constraint
    execute <<-SQL
      ALTER TABLE legacy_value_mappings
      DROP CONSTRAINT new_value_pattern_check;
    SQL

    # Re-add the original check constraint
    execute <<-SQL
      ALTER TABLE legacy_value_mappings
      ADD CONSTRAINT legacy_and_new_value_pattern_check
      CHECK ((legacy_value ~ '^0x[a-f0-9]{64}$' AND new_value ~ '^0x[a-f0-9]{64}$') OR (legacy_value ~ '^0x[a-f0-9]{40}$' AND new_value ~ '^0x[a-f0-9]{40}$'));
    SQL
  end
end
