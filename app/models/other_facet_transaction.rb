class OtherFacetTransaction < ApplicationRecord
  self.abstract_class = true
  establish_connection :other_development

  # Define the table name if it's different
  self.table_name = 'facet_transactions'
end
