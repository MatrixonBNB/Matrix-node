class LegacyContractArtifact < ApplicationRecord
  self.table_name = "contract_artifacts"
  
  def self.cached_all
    @cached_all ||= reading { all }
  end
  
  def self.shortest_unique_suffix_length
    strings = cached_all.map(&:init_code_hash)
    
    max_length = strings.map(&:length).max
    length = 1
    
    while length <= max_length
      suffixes = strings.map { |str| str.last(length) }
      return length if suffixes.uniq.size == strings.size
      length += 1
    end
    
    max_length
  end
  
  def self.address_from_suffix(suffix)
    suffix = suffix.last(3).downcase
    artifact = find_by_suffix(suffix)
    
    "0x" + artifact.init_code_hash.last(40)
  end
  
  def self.find_by_suffix(suffix)
    candidate = cached_all.select do |artifact|
      artifact.init_code_hash.last(suffix.length) == suffix
    end
       
    raise "Ambiguous suffix: #{suffix}, #{candidate.map(&:init_code_hash)}" if candidate.size != 1
    
    candidate.first
  end
end
