class LegacyValueMapping < ApplicationRecord
  validates :mapping_type, :legacy_value, :new_value, presence: true
  
  def self.to_file(filename)
    json = JSON.pretty_generate(LegacyValueMapping.all.map(&:as_json))
    File.write(filename, json)
  end
end
