class RemoveSizeNonNullFromFacetBlocks < ActiveRecord::Migration[7.1]
  def up
    change_column_null :facet_blocks, :size, true
  end

  def down
  end
end
