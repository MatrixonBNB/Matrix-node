class LegacyValueMapping < ApplicationRecord
  validates :mapping_type, :legacy_value, :new_value, presence: true
end
