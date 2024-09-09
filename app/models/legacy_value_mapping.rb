class LegacyValueMapping < ApplicationRecord
  class NoMappingSource < StandardError; end
  
  def self.to_file(network = ENV.fetch('L1_NETWORK'))
    json = JSON.pretty_generate(as_hash)
    File.write(file_location(network), json)
  end
  
  def self.file_location(network = ENV.fetch('L1_NETWORK'))
    Rails.root.join('config', "legacy-value-mappings-#{network}.json")
  end
  
  def self.as_hash
    all.each_with_object({}) do |mapping, hash|
      hash[mapping.legacy_value] = mapping.new_value
    end.sort_by { |k, _| [k.length, k] }.to_h
  end
  
  def self.memoized_file_contents(network = ENV.fetch('L1_NETWORK'))
    @memoized_file_contents ||= JSON.parse(File.read(file_location(network)))
  end
  
  def self.lookup(legacy_value)
    if LegacyMigrationDataGenerator.instance.current_import_block_number
      raise "Legacy value mapping is not available during legacy data generation"
    end
    
    if oracle_base_url.present?
      oracle_lookup(legacy_value)
    elsif File.exist?(file_location)
      memoized_file_contents.fetch(legacy_value)
    else
      raise NoMappingSource, "No source of truth for legacy value mapping: #{legacy_value}"
    end
  end
  
  def self.oracle_lookup(legacy_value)
    endpoint = '/legacy_value_mappings/lookup'
    query_params = {
      legacy_value: legacy_value
    }

    response = HttpPartyWithRetry.get_with_retry("#{oracle_base_url}#{endpoint}", query: query_params)
    parsed_response = JSON.parse(response.body)
    parsed_response.fetch('new_value')
  end
  
  def self.oracle_base_url
    ENV["LEGACY_VALUE_ORACLE_URL"].presence
  end
end
