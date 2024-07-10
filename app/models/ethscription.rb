class Ethscription < ApplicationRecord
  include Memery
  class << self
    include Memery
  end
  
  class FunctionMissing < StandardError; end
  class InvalidArgValue < StandardError; end
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
      
      TransactionHelper.get_deploy_data(
        'legacy/ERC1967Proxy', [predeploy_address, initialize_calldata]
      )
    elsif content['op'] == 'call'
      to_address = calculate_to_address(data['to'], block_number)
      
      implementation_address = get_implementation(to_address)
      
      unless implementation_address
        # binding.irb
        raise "No implementation address for #{to_address}"
      end
      
      contract_name = local_from_predeploy(implementation_address)
      args = convert_args(contract_name, data['function'], data['args'])
      
      TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: data['function'],
        args: args
      )
    else
      raise "Unsupported operation: #{content['op']}"
    end
  rescue FunctionMissing, InvalidArgValue => e
    data['args'].to_json.bytes_to_hex
  rescue ContractMissing => e
    data['to']
  rescue KeyError => e
    ap content
    # binding.irb
    raise
  rescue => e
    # binding.irb
    raise
  end
  
  def facet_tx_to
    return if parsed_content['op'] == 'create'
    calculate_to_address(parsed_content['data']['to'], block_number)
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
    
    def calculate_to_address(legacy_to, block_number)
      deploy_receipt = FacetTransactionReceipt.find_by("legacy_contract_address_map ? :legacy_to", legacy_to: legacy_to)
      
      unless deploy_receipt
        raise ContractMissing, "Contract #{legacy_to} not found"
      end
      
      deploy_receipt.legacy_contract_address_map[legacy_to]
    end
    memoize :calculate_to_address
  end
  delegate :calculate_to_address, to: :class
  delegate :get_implementation, to: :class
  
  def self.t
    no_ar_logging; EthBlock.delete_all; reload!; 50.times{EthBlockImporter.import_next_block;}
  end
  
  def convert_args(contract, function_name, args)
    contract = EVMHelpers.compile_contract(contract)
    function = contract.functions.find { |f| f.name == function_name }
    
    unless function
      raise FunctionMissing, "Function #{function_name} not found in #{contract}"
    end
    
    inputs = function.inputs
    
    args = [args] if args.is_a?(String) || args.is_a?(Integer)
    
    if args.is_a?(Hash)
      args_hash = args.with_indifferent_access
      args = inputs.map do |input|
        args_hash[input.name]
      end
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
  
  def self.predeploy_to_local_map
    legacy_dir = Rails.root.join("lib/solidity/legacy")
    map = {}
    
    Dir.glob("#{legacy_dir}/*.sol").each do |file_path|
      filename = File.basename(file_path, ".sol")
  
      if filename.match(/V[a-f0-9]{3}$/i)
        logger.info("Retreiving address of #{filename}")
        address = LegacyContractArtifact.address_from_suffix(filename)
        logger.info("Address of #{filename} is #{address}")
        map[address] = filename
  
        # Compile the contract and add to the map using init_code_hash
        contract = EVMHelpers.compile_contract("legacy/#{filename}")
        map["0x" + contract.parent.init_code_hash.last(40)] = filename
      end
    end 
    
    map["0x00000000000000000000000000000000000000c5"] = "NonExistentContractShim"
    
    map
  end
  
  def self.local_from_predeploy(address)
    name = predeploy_to_local_map.fetch(address.downcase)
    logger.info("Retreiving #{name} for #{address}")
    "legacy/#{name}"
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
