class LegacyValueMapping < ApplicationRecord
  def self.to_file(filename)
    json = JSON.pretty_generate(LegacyValueMapping.all.map(&:as_json))
    File.write(filename, json)
  end
end
