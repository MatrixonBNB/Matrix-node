class CreateLegacyValueMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :legacy_value_mappings do |t|
      t.string :legacy_value, null: false
      t.string :new_value, null: false
      
      t.index :legacy_value, unique: true
      
      t.check_constraint "(legacy_value ~ '^0x[a-f0-9]{64}$' AND new_value ~ '^0x[a-f0-9]{64}$') OR (legacy_value ~ '^0x[a-f0-9]{40}$' AND new_value ~ '^0x[a-f0-9]{40}$')", name: "legacy_and_new_value_pattern_check"
      
      t.timestamps
    end
  end
end
