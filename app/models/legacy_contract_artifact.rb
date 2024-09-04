class LegacyContractArtifact < ApplicationRecord
  include LegacyModel
  
  class LegacyContractArtifactStruct < T::Struct
    const :id, Integer
    const :transaction_hash, String
    const :internal_transaction_index, Integer
    const :block_number, Integer
    const :transaction_index, Integer
    const :name, String
    const :source_code, String
    const :init_code_hash, String
    const :references, T::Array[T::Hash[String, T.nilable(String)]]
    const :pragma_language, String
    const :pragma_version, String
    const :created_at, String
    const :updated_at, String
  end
  
  class AmbiguousSuffixError < StandardError; end
  include Memery
  self.table_name = "contract_artifacts"
  
  scope :oldest_first, -> { order(:block_number, :transaction_index, :internal_transaction_index) }
  scope :newest_first, -> { order(block_number: :desc, transaction_index: :desc, internal_transaction_index: :desc) }
  
  def self.all_json
    if base_url = LegacyValueMapping.oracle_base_url
      endpoint = '/legacy_value_mappings/contract_artifacts'
      
      response = HttpPartyWithRetry.get_with_retry("#{base_url}#{endpoint}")
      response.body
    else
      LegacyContractArtifact.all.oldest_first.to_json
    end
  end
  
  def self.cached_all
    @_cached_all ||= begin
      parsed = JSON.parse(all_json)
      
      parsed.map do |artifact|
        begin
          LegacyContractArtifactStruct.new(**artifact.symbolize_keys)
        rescue => e
          binding.irb
          raise
        end
      end
    end
  end
  
  def self.find_by_name(name)
    artifacts = cached_all.select { |artifact| artifact.name == name }
    unless artifacts.size == 1
      raise "Ambiguous name: #{name}, #{artifacts.map(&:name)}"
    end
    artifacts.first
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
  
  def self.find_next_artifact(current_artifact)
    primary_contract_name = extract_primary_contract_name(current_artifact.source_code)
    artifacts = cached_all.select do |artifact|
      extract_primary_contract_name(artifact.source_code) == primary_contract_name
    end

    current_index = artifacts.index(current_artifact)
    return nil if current_index.nil? || current_index + 1 >= artifacts.size

    artifacts[current_index + 1]
  end
  
  def self.diff_to_next_version(current_suffix)
    current_artifact = find_by_suffix(current_suffix)
    current_name = current_artifact.primary_contract_name + "V#{current_suffix}"
    next_artifact = find_next_artifact(current_artifact)
    return puts "No next version found for #{current_name}" unless next_artifact

    next_suffix = next_artifact.init_code_hash.last(3)
    next_name = current_name.gsub("V#{current_suffix}", "V#{next_suffix}")

    legacy_dir = Rails.root.join("lib/solidity/legacy")
    current_file_path = "#{legacy_dir}/#{current_name}.sol"
    next_file_path = "#{legacy_dir}/#{next_name}.sol"
    
    unless File.exist?(current_file_path)
      raise "File #{current_file_path} does not exist"
    end

    unless File.exist?(next_file_path)
      FileUtils.cp(current_file_path, next_file_path)
      puts "Created new version file: #{next_file_path}"
    end

    current_source = current_artifact.source_code
    next_source = next_artifact.source_code

    diff = Diffy::Diff.new(current_source, next_source, context: 3).to_s(:html)
    
    diff_file_path = "#{legacy_dir}/#{current_name}_to_#{next_name}.html"
    File.open(diff_file_path, 'w') do |file|
      file.write("<html><head><style>#{Diffy::CSS}</style></head><body>")
      file.write(diff)
      file.write("</body></html>")
    end
    puts "Diff saved to: #{diff_file_path}"
  end
  
  def name_and_suffix
    "#{primary_contract_name}V#{init_code_hash.last(3)}"
  end
  
  def primary_contract_name
    self.class.extract_primary_contract_name(source_code)
  end
  memoize :primary_contract_name
  
  def self.extract_primary_contract_name(source_code)
    primary_contract = nil

    # Define a dummy context with a contract method
    context = BasicObject.new
    singleton_class = class << context; self; end
    singleton_class.define_method(:contract) do |name, *|
      primary_contract = name
    end

    # Use method_missing to ignore other methods
    singleton_class.define_method(:method_missing) { |*| }

    # Evaluate the source code in the context
    context.instance_eval(source_code)

    primary_contract.to_s.gsub(/V\d+$/, '').gsub(/0\d$/, '').gsub("V1", '')
  end
  
  def self.diff_source_code(artifact1, artifact2)
    source1 = artifact1.source_code
    source2 = artifact2.source_code

    diff = Diffy::Diff.new(source1, source2, context: 3).to_s(:color)
    puts diff
  end
  
  def self.diff_artifacts_with_same_primary_contract
    artifacts_by_contract = cached_all.group_by do |artifact|
      extract_primary_contract_name(artifact.source_code)
    end

    artifacts_by_contract.each do |contract_name, artifacts|
      next if artifacts.size < 2 # Skip if there are less than 2 artifacts for the contract

      artifacts.combination(2).each do |artifact1, artifact2|
        puts "Diff between #{artifact1.name} and #{artifact2.name} for contract #{contract_name}:"
        diff_source_code(artifact1, artifact2)
      end
    end
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
       
    if candidate.size != 1
      raise AmbiguousSuffixError, "Ambiguous suffix: #{suffix}, #{candidate.map(&:init_code_hash)}"
    end
    
    candidate.first
  end
end
