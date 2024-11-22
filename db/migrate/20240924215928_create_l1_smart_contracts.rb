class CreateL1SmartContracts < ActiveRecord::Migration[7.1]
  def change
    create_table :l1_smart_contracts do |t|
      t.string :address, null: false
      t.bigint :block_number, null: false

      t.timestamps
      
      t.index :address, unique: true
      if pg_adapter?
        t.check_constraint "address ~ '^0x[0-9a-f]{40}$'"
      end
    end
  end
end
