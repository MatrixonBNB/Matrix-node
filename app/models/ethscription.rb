class Ethscription < ApplicationRecord
  include Memery
  class << self
    include Memery
  end
  
  class FunctionMissing < StandardError; end
  class InvalidArgValue < StandardError; end
  class InvalidNumberOfArgs < StandardError; end
  class ContractMissing < StandardError; end
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true, autosave: false
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash, optional: true, autosave: false
  has_one :facet_transaction, primary_key: :transaction_hash, foreign_key: :tx_hash
  has_one :facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  has_one :legacy_facet_transaction, primary_key: :transaction_hash, foreign_key: :transaction_hash
  has_one :legacy_facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  delegate :get_code, :local_from_predeploy, :predeploy_to_local_map, to: :class
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  def block_hash
    block_blockhash
  end
  
  def parsed_content
    JSON.parse(content)
  end
  
  def self.required_initial_owner
    "0x00000000000000000000000000000000000face7"
  end
  
  def self.transaction_mimetype
    "application/vnd.facet.tx+json"
  end
  
  def valid_to?
    initial_owner == self.class.required_initial_owner
  end
  
  def valid_mimetype?
    mimetype == self.class.transaction_mimetype
  end
  
  def contract_transaction?
    valid_mimetype? && valid_to? && processing_state == 'success'
  end
  
  def facet_tx_input
    content = parsed_content
    data = content['data']
    
    if content['op'] == 'create'
      predeploy_address = "0x" + data['init_code_hash'].last(40)
      
      contract_name = local_from_predeploy(predeploy_address)
      args = convert_args(contract_name, 'initialize', data['args'])
      
      initialize_calldata = TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: 'initialize',
        args: args
      )
      
      EVMHelpers.get_deploy_data(
        'legacy/ERC1967Proxy', [predeploy_address, initialize_calldata]
      )
    elsif content['op'] == 'call'
      clear_caches_if_upgrade!
      
      to_address = calculate_to_address(data['to'])
      
      if data['function'] == 'upgradePairs'
        data['args']['pairs'] = data['args']['pairs'].map do |pair|
          Ethscription.calculate_to_address(pair)
        end
      end
      
      implementation_address = get_implementation(to_address)
      
      unless implementation_address
        # binding.irb
        raise "No implementation address for #{to_address}"
      end
      
      contract_name = local_from_predeploy(implementation_address)
      args = convert_args(contract_name, data['function'], data['args'])
      
      if data['function'] == 'upgradeAndCall'
        new_impl_address = "0x" + args.first.last(40)
        new_contract_name = local_from_predeploy(new_impl_address)
        migrationCalldata = JSON.parse(args.last)
        migration_args = convert_args(
          new_contract_name,
          migrationCalldata['function'],
          migrationCalldata['args']
        )
        
        cooked = TransactionHelper.get_function_calldata(
          contract: new_contract_name,
          function: migrationCalldata['function'],
          args: migration_args
        )
        
        args[1] = ''
        
        args[2] = cooked
      end
      
      clear_caches_if_upgrade!

      TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: data['function'],
        args: args
      )
    else
      raise "Unsupported operation: #{content['op']}"
    end
  rescue FunctionMissing, InvalidArgValue, InvalidNumberOfArgs, Eth::Abi::EncodingError => e
    # ap e
    # puts [contract_name, data['function'], data['args']].inspect
    # binding.irb
    message = "Invalid function call: #{e.message}"
    message.bytes_to_hex
  rescue ContractMissing => e
    data['to']
  rescue KeyError => e
    ap content
    binding.irb
    raise
  rescue => e
    binding.irb
    raise
  end
  
  def is_upgrade?
    content = parsed_content
    data = content['data']
    fn = data['function']
    
    ['upgradeAndCall', 'upgrade', 'upgradePairs', 'upgradePair'].include?(fn)
  end
  
  def clear_caches!
    SolidityCompiler.reset_checksum
    Rails.cache.clear
    MemeryExtensions.clear_all_caches!
  end
  
  def clear_caches_if_upgrade!
    clear_caches! if is_upgrade?
  end
  
  def facet_tx_to
    return if parsed_content['op'] == 'create'
    calculate_to_address(parsed_content['data']['to'])
  rescue ContractMissing => e
    "0x00000000000000000000000000000000000000c5"
  end
  
  class << self
    def get_implementation(to_address)
      Rails.cache.fetch([to_address, '__getImplementation', Rails.env]) do
        TransactionHelper.static_call(
          contract: 'legacy/ERC1967Proxy',
          address: to_address,
          function: '__getImplementation',
          args: []
        )
      end
    end
    memoize :get_implementation
    
    def calculate_to_address(legacy_to)
      deploy_receipt = FacetTransactionReceipt.find_by("legacy_contract_address_map ? :legacy_to", legacy_to: legacy_to)
      
      unless deploy_receipt
        raise ContractMissing, "Contract #{legacy_to} not found"
      end
      
      deploy_receipt.legacy_contract_address_map[legacy_to]
    end
    memoize :calculate_to_address
    
    def convert_args(contract_name, function_name, args)
      contract = EVMHelpers.compile_contract(contract_name)
      function = contract.functions.find { |f| f.name == function_name }
      
      unless function
        # If the function is missing, try to find the next implementation
        current_suffix = contract_name.last(3)
        current_artifact = LegacyContractArtifact.find_by_suffix(current_suffix)
        
        next_artifact = LegacyContractArtifact.find_next_artifact(current_artifact)
        if next_artifact
          next_artifact_suffix = next_artifact.init_code_hash.last(3)
        
          next_artifact_name = contract_name.gsub(current_suffix, next_artifact_suffix)
          
          contract = EVMHelpers.compile_contract(next_artifact_name)
          function = contract.functions.find { |f| f.name == function_name }
          
          unless function
            raise FunctionMissing, "Function #{function_name} not found in #{contract} or its next implementation"
          end
        else
          raise FunctionMissing, "Function #{function_name} not found in #{contract} and no next implementation found"
        end
      end
      
      inputs = function.inputs
      
      if inputs.empty? && args.nil?
        return []
      end
      
      args = [args] if args.is_a?(String) || args.is_a?(Integer)
      
      if args.is_a?(Hash)
        args_hash = args.with_indifferent_access
        if args_hash.size != inputs.size
          raise InvalidNumberOfArgs, "Expected #{inputs.size} arguments, got #{args_hash.size}"
        end
        args = inputs.map do |input|
          if input.name == 'withdrawalId'
            real_withdrawal_id(args_hash[input.name])
          else
            args_hash[input.name]
          end
        end
      elsif args.is_a?(Array)
        if args.size != inputs.size
          raise InvalidNumberOfArgs, "Expected #{inputs.size} arguments, got #{args.size}"
        end
        args = args.each_with_index.map do |arg, index|
          if inputs[index].name == 'withdrawalId'
            real_withdrawal_id(arg)
          else
            arg
          end
        end
      else
        raise ArgumentError, "Expected arguments to be a Hash or Array, got #{args.class}"
      end
      
      args = normalize_args(args, inputs)
      
      args
    rescue ArgumentError => e
      if e.message.include?("invalid value for Integer()")
        raise InvalidArgValue, "Invalid value: #{e.message.split(':').last.strip}"
      else
        raise
      end
    end
    memoize :convert_args
    
    def normalize_args(args, inputs)
      args&.each_with_index&.map do |arg_value, idx|
        input = inputs[idx]
        normalize_arg_value(arg_value, input)
      end
    end
  
    def normalize_arg_value(arg_value, input)
      if arg_value.is_a?(String) && (input.type.starts_with?('uint') || input.type.starts_with?('int'))
        Integer(arg_value, 10)
      elsif arg_value.is_a?(Array)
        arg_value.map do |val|
          normalize_arg_value(val, input)
        end
      else
        arg_value
      end
    end
    
    def real_withdrawal_id(user_withdrawal_id)
      receipt = FacetTransaction.find_by!(eth_transaction_hash: user_withdrawal_id).facet_transaction_receipt
      receipt.decoded_legacy_logs.
        detect { |i| i['event'] == 'InitiateWithdrawal' }['data']['withdrawalId'].bytes_to_hex
    rescue ActiveRecord::RecordNotFound => e
      raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
    end
  end
  delegate :calculate_to_address, to: :class
  delegate :get_implementation, to: :class
  delegate :convert_args, to: :class
  delegate :normalize_args, to: :class
  delegate :normalize_arg_value, to: :class
  delegate :real_withdrawal_id, to: :class
  
  def self.t
    no_ar_logging; EthBlock.delete_all; reload!; 50.times{EthBlockImporter.import_next_block;}
  end
  
  class << self
    def predeploy_to_local_map
      legacy_dir = Rails.root.join("lib/solidity/legacy")
      map = {}
      
      Dir.glob("#{legacy_dir}/*.sol").each do |file_path|
        filename = File.basename(file_path, ".sol")
    
        if filename.match(/V[a-f0-9]{3}$/i)
          address = LegacyContractArtifact.address_from_suffix(filename)
          map[address] = filename
    
          # Compile the contract and add to the map using init_code_hash
          contract = EVMHelpers.compile_contract("legacy/#{filename}")
          map["0x" + contract.parent.init_code_hash.last(40)] = filename
        end
      end 
      
      map["0x00000000000000000000000000000000000000c5"] = "NonExistentContractShim"
      
      map
    end
    memoize :predeploy_to_local_map
    
    def local_from_predeploy(address)
      name = predeploy_to_local_map.fetch(address.downcase)
      "legacy/#{name}"
    end
    memoize :local_from_predeploy
  end
  
  def self.get_code(address)
    local = local_from_predeploy(address)
    contract = EVMHelpers.compile_contract(local)
    raise unless contract.parent.bin_runtime
    contract.parent.bin_runtime
  end
  
  def self.generate_alloc_for_genesis
    predeploy_to_local_map.map do |address, alloc|
      [
        address,
        {
          "code" => "0x" + get_code(address),
          "balance" => 0
        }
      ]
    end.to_h
  end
  
  def self.write_alloc_to_genesis
    SolidityCompiler.reset_checksum
    SolidityCompiler.compile_all_legacy_files
    
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')
    genesis_path = File.join(geth_dir, 'facet-chain', 'genesis3.json')

    # Read the existing genesis.json file
    genesis_data = JSON.parse(File.read(genesis_path))

    # Overwrite the "alloc" key with the new allocation
    genesis_data['alloc'] = generate_alloc_for_genesis

    # Write the updated data back to the genesis.json file
    File.write(genesis_path, JSON.pretty_generate(genesis_data))
  end
end
