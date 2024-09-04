class LegacyValueMapping < ApplicationRecord
  def self.to_file(filename)
    json = JSON.pretty_generate(LegacyValueMapping.all.map(&:as_json))
    File.write(filename, json)
  end
  
  def self.oracle_base_url
    ENV["LEGACY_VALUE_ORACLE_URL"]
  end
end
