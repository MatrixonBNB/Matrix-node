class CreateLegacyValueMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :legacy_value_mappings do |t|
      t.string :mapping_type, null: false
      t.string :legacy_value, null: false
      t.string :new_value, null: false
      
      # t.string :created_by_eth_transaction_hash, null: false
      
      t.index [:mapping_type, :legacy_value], unique: true
      # t.index [:mapping_type, :new_value], unique: true
      
      t.check_constraint "mapping_type IN ('address', 'withdrawal_id')"
      
      t.check_constraint "CASE 
        WHEN mapping_type = 'withdrawal_id' THEN legacy_value ~ '^0x[a-f0-9]{64}$' AND new_value ~ '^0x[a-f0-9]{64}$'
        WHEN mapping_type = 'address' THEN legacy_value ~ '^0x[a-f0-9]{40}$' AND new_value ~ '^0x[a-f0-9]{40}$'
        ELSE FALSE
      END"
      
      # t.check_constraint "created_by_eth_transaction_hash ~ '^0x[a-f0-9]{64}$'"
      
      t.timestamps
    end
  end
end
