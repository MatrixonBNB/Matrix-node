class RemoveMappingCheckConstraint < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :legacy_value_mappings, name: 'chk_rails_48ee1bf62a'
  end
  
  def down
    
  end
end
