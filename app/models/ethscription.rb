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
    parsed_data_uri&.decoded_data
  end
  
  def valid_data_uri?
    DataUri.valid?(content_uri)
  end
  
  def parsed_data_uri
    return unless valid_data_uri?
    DataUri.new(content_uri)
  end
  
  def block_hash
    block_blockhash
  end
  
  def parsed_content
    JSON.parse(content)
  end
  
  def mimetype
    parsed_data_uri&.mimetype
  end
  
  def payload
    OpenStruct.new(JSON.parse(content))
  rescue JSON::ParserError, NoMethodError => e
    nil
  end
  
  def valid_ethscription?
    v = valid_data_uri? &&
    valid_to? &&
    valid_mimetype? &&
    (payload.present? && payload.data&.is_a?(Hash))
    
    return false unless v
    
    op = payload.op&.to_sym
    data_keys = payload.data.keys.map(&:to_sym).to_set
    
    if op == :create
      unless [
        [:init_code_hash].to_set,
        [:init_code_hash, :args].to_set,
        
        [:init_code_hash, :source_code].to_set,
        [:init_code_hash, :source_code, :args].to_set
      ].include?(data_keys)
        return false
      end
    end
    
    if [:call, :static_call].include?(op)
      unless [
        [:to, :function].to_set,
        [:to, :function, :args].to_set
      ].include?(data_keys)
        return false
      end
      
      unless payload.data['to'].to_s.match(/\A0x[a-f0-9]{40}\z/i)
        return false
      end
    end
    
    unless DataUri.esip6?(content_uri)
      binding.irb
      raise
    end
    
    true
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
  
  def self.from_eth_transactions(eth_transactions)
    eth_transactions.map(&:init_ethscription).compact.flatten
  end
  
  def facet_tx_input
    content = parsed_content
    data = content['data']
    
    if content['op'] == 'create'
      predeploy_address = "0x" + data['init_code_hash'].last(40)
      
      begin
        contract_name = local_from_predeploy(predeploy_address)
      rescue KeyError => e
        if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
          return predeploy_address
        else
          ap content
          binding.irb
          raise
        end
      end
      
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
        if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
          return "0x" + "0" * 100
        else
          binding.irb
          raise "No implementation address for #{to_address}"
        end
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
      elsif data['function'] == 'setMetadataRenderer'
        begin
          metadata_calldata = JSON.parse(data['args'].is_a?(Array) ? data['args'].last : data['args']['data'])
        rescue JSON::ParserError => e
          raise unless ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
          metadata_calldata = {"function" => "", "args" => {}}
        end
        
        target_contract_name = if metadata_calldata['args'].keys == ['info']
          "legacy/EditionMetadataRendererV3f8"
        else
          "legacy/TokenUpgradeRendererVbf5"
        end
        
        metadata_args = convert_args(
          target_contract_name,
          metadata_calldata['function'],
          metadata_calldata['args']
        )
        
        cooked_metadata = TransactionHelper.get_function_calldata(
          contract: target_contract_name,
          function: metadata_calldata['function'],
          args: metadata_args.map(&:to_h)
        )
        
        args[1] = cooked_metadata.hex_to_bytes
      elsif data['function'] == 'bridgeAndCall'
        base64_input = data['args'].is_a?(Hash) ? data['args']['base64Calldata'] : data['args'].last
        decoded_input = Base64.strict_decode64(base64_input)
        
        to_address = calculate_to_address(data['args'].is_a?(Hash) ? data['args']['addressToCall'] : data['args'].third)
        implementation_address = get_implementation(to_address)
        sub_contract_name = local_from_predeploy(implementation_address)
        
        bridge_calldata = begin
          json_input = JSON.parse(decoded_input)
          
          bridge_args = convert_args(
            sub_contract_name,
            json_input['function'],
            json_input['args']
          )
          
          TransactionHelper.get_function_calldata(
            contract: sub_contract_name,
            function: json_input['function'],
            args: bridge_args
          )
        rescue JSON::ParserError => e
          "__invalidJSON__: #{e.message}".bytes_to_hex
        end
                
        encoded_calldata = Base64.strict_encode64(bridge_calldata.hex_to_bytes)
        args[3] = encoded_calldata
        # binding.irb
      elsif data['function'] == 'callBuddyForUser'
        input = data['args'].is_a?(Hash) ? data['args']['calldata'] : data['args'].last
        decoded_input = input
        
        to_address = calculate_to_address(data['args'].is_a?(Hash) ? data['args']['addressToCall'] : data['args'].second)
        implementation_address = get_implementation(to_address)
        sub_contract_name = local_from_predeploy(implementation_address)
        
        factory_calldata = begin
          json_input = JSON.parse(decoded_input)
          
          function = json_input.is_a?(Hash) ? json_input['function'] : json_input.first
          function_args = json_input.is_a?(Hash) ? json_input['args'] : json_input[1..-1]
          
          buddy_args = convert_args(
            sub_contract_name,
            function,
            function_args
          )
          
          TransactionHelper.get_function_calldata(
            contract: sub_contract_name,
            function: function,
            args: buddy_args
          )
        rescue JSON::ParserError => e
          "__invalidJSON__: #{e.message}".bytes_to_hex
        end
        
        args[2] = factory_calldata.hex_to_bin
      elsif data['function'] == 'bridgeOut' && contract_name == "legacy/ERC20BridgeFactoryVce0"
        # TransactionHelper.static_call(
        #   contract: "legacy/ERC20BridgeFactoryVce0",
        #   address: to_address,
        #   function: 'bridgeDumbContractToTokenSmartContract',
        #   args: [data['args']['bridgeDumbContract']]
        # )
        if TransactionHelper.code_at_address(args[0]) == "0x"
          args[0] = calculate_to_address(args[0])
        end
      elsif ['addLiquidity', 'removeLiquidity'].include?(data['function'])
        token_a = args[0].downcase
        token_b = args[1].downcase
        
        if TransactionHelper.code_at_address(token_a) == "0x"
          args[0] = calculate_to_address(token_a)
        end
        
        if TransactionHelper.code_at_address(token_b) == "0x"
          args[1] = calculate_to_address(token_b)
        end
      elsif data['function'] == 'swapExactTokensForTokens'
        path = args[2].map(&:downcase)
        path.each_with_index do |token, index|
          if TransactionHelper.code_at_address(token) == "0x"
            path[index] = calculate_to_address(token)
          end
        end
        
        args[2] = path
      elsif data['function'] == 'batchTransfer'
        if TransactionHelper.code_at_address(args[0]) == "0x"
          args[0] = calculate_to_address(args[0])
        end
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
  rescue FunctionMissing, InvalidArgValue, InvalidNumberOfArgs, Eth::Abi::EncodingError, Eth::Abi::ValueOutOfBounds => e
    # ap e
    # puts [contract_name, data['function'], data['args']].inspect
    message = "Invalid function call: #{e.message}"
    message.bytes_to_hex
  rescue ContractMissing => e
    data['to']
  rescue KeyError => e
    if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
      return content.to_json.bytes_to_hex
    else
      ap content
      binding.irb
      raise
    end
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
    shim_val = "0x00000000000000000000000000000000000000c5"
    
    unless ENV['LEGACY_VALUE_ORACLE_URL']
      LegacyValueMapping.find_or_create_by!(
        mapping_type: :address,
        legacy_value: parsed_content['data']['to'].downcase,
        new_value: shim_val
      )
    end
    
    shim_val
  end
  
  class << self
    def get_implementation(to_address)
      TransactionHelper.static_call(
        contract: 'legacy/ERC1967Proxy',
        address: to_address,
        function: '__getImplementation',
        args: []
      ).freeze
    end
    memoize :get_implementation
    
    def calculate_to_address(legacy_to)
      legacy_to = legacy_to.downcase
      
      if ENV['LEGACY_VALUE_ORACLE_URL']
        new_value = lookup_new_value(
          type: :address,
          legacy_value: legacy_to
        )
        
        return new_value if new_value
        
        raise "Withdrawal ID not found: #{legacy_to}"
      end
      
      BlockImportBatchContext.imported_facet_transaction_receipts&.each do |receipt|
        if receipt.legacy_contract_address_map.key?(legacy_to)
          return receipt.legacy_contract_address_map[legacy_to]
        end
      end  
      
      deploy_receipt = FacetTransactionReceipt.find_by("legacy_contract_address_map ? :legacy_to", legacy_to: legacy_to)
      
      unless deploy_receipt
        # binding.irb
        raise ContractMissing, "Contract #{legacy_to} not found"
      end
      
      new_to = deploy_receipt.legacy_contract_address_map[legacy_to]
      
      LegacyValueMapping.find_or_create_by!(
        mapping_type: 'address',
        legacy_value: legacy_to,
        new_value: new_to,
        # created_by_eth_transaction_hash: self.transaction_hash
      )
      
      new_to
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
            raise FunctionMissing, "Function #{function_name} not found in #{contract.name} or its next implementation"
          end
        else
          raise FunctionMissing, "Function #{function_name} not found in #{contract.name} and no next implementation found"
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
    rescue Errno::ENOENT, LegacyContractArtifact::AmbiguousSuffixError => e
      if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
        raise FunctionMissing, "Function #{function_name} not found"
      else
        binding.irb
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
        base = arg_value.start_with?('0x') ? 16 : 10
        Integer(arg_value, base)
      elsif arg_value.is_a?(Array)
        arg_value.map do |val|
          normalize_arg_value(val, input)
        end
      else
        arg_value
      end
    end
    
    def lookup_new_value(type:, legacy_value:)
      base_url = ENV.fetch('LEGACY_VALUE_ORACLE_URL')
      endpoint = '/legacy_value_mappings/lookup'
      query_params = {
        mapping_type: type,
        legacy_value: legacy_value
      }
  
      response = HttpPartyWithRetry.get_with_retry("#{base_url}#{endpoint}", query: query_params)
      parsed_response = JSON.parse(response.body)
  
      if parsed_response['new_value']
        if parsed_response['new_value'] == "0x00000000000000000000000000000000000000c5"
          raise ContractMissing, "Contract #{legacy_value} not found"
        end
        
        if parsed_response['new_value'] == "0x" + "0" * 62 + "c5"
          raise InvalidArgValue, "Withdrawal ID not found: #{legacy_value}"
        end
        
        return parsed_response['new_value']
      end
    end
    memoize :lookup_new_value
    
    def real_withdrawal_id(user_withdrawal_id)
      if ENV['LEGACY_VALUE_ORACLE_URL']
        new_value = lookup_new_value(
          type: :withdrawal_id,
          legacy_value: user_withdrawal_id
        )
        
        return new_value if new_value
        
        raise "Withdrawal ID not found: #{user_withdrawal_id}"
      end
      
      # Check in-memory cache first
      transaction = BlockImportBatchContext.imported_facet_transactions&.find { |tx| tx.eth_transaction_hash == user_withdrawal_id }
      
      if transaction
        receipt = BlockImportBatchContext.imported_facet_transaction_receipts.find { |r| r.transaction_hash == transaction.tx_hash }
      else
        # Fallback to database query
        transaction = FacetTransaction.find_by(eth_transaction_hash: user_withdrawal_id)
        if transaction
          receipt = transaction.facet_transaction_receipt
        else
          LegacyValueMapping.find_or_create_by!(
            mapping_type: 'withdrawal_id',
            legacy_value: user_withdrawal_id,
            new_value: "0x" + "0" * 62 + "c5",
          )
          
          raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
        end
      end
      
      unless receipt
        # binding.irb
        LegacyValueMapping.find_or_create_by!(
          mapping_type: 'withdrawal_id',
          legacy_value: user_withdrawal_id,
          new_value: "0x" + "0" * 62 + "c5",
        )
        
        raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
      end
      
      if receipt.status == 0
        LegacyValueMapping.find_or_create_by!(
          mapping_type: 'withdrawal_id',
          legacy_value: user_withdrawal_id,
          new_value: user_withdrawal_id,
        )
        
        return user_withdrawal_id
      end
      
      new_withdrawal_id = receipt.decoded_legacy_logs.
        detect { |i| i['event'] == 'InitiateWithdrawal' }['data']['withdrawalId']
      
      LegacyValueMapping.find_or_create_by!(
        mapping_type: 'withdrawal_id',
        legacy_value: user_withdrawal_id,
        new_value: new_withdrawal_id,
      )
      
      new_withdrawal_id
    rescue ActiveRecord::RecordNotFound => e
      LegacyValueMapping.find_or_create_by!(
        mapping_type: 'withdrawal_id',
        legacy_value: user_withdrawal_id,
        new_value: "0x" + "0" * 62 + "c5",
      )
      
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
          begin
            address = LegacyContractArtifact.address_from_suffix(filename)
          rescue LegacyContractArtifact::AmbiguousSuffixError => e
            next if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
            raise
          end
          
          map[address] = filename
    
          # Compile the contract and add to the map using init_code_hash
          contract = EVMHelpers.compile_contract("legacy/#{filename}")
          map["0x" + contract.parent.init_code_hash.last(40)] = filename
        end
      end 
      
      map["0x00000000000000000000000000000000000000c5"] = "NonExistentContractShim"
      map["0x4200000000000000000000000000000000000015"] = "L1Block"
      
      map
    end
    memoize :predeploy_to_local_map
    
    def local_from_predeploy(address)
      name = predeploy_to_local_map.fetch(address&.downcase)
      "legacy/#{name}"
    end
    memoize :local_from_predeploy
  end
  
  def self.get_code(address)
    local = local_from_predeploy(address)
    contract = EVMHelpers.compile_contract(local)
    raise unless contract.parent.bin_runtime
    unless is_valid_hex?("0x" + contract.parent.bin_runtime)
      binding.irb
      raise
    end
    contract.parent.bin_runtime
  end
  
  def self.is_valid_hex?(hex)
    hex.match?(/^0x[0-9a-fA-F]+$/) && hex.length.even?
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
    Rails.cache.clear
    MemeryExtensions.clear_all_caches!
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
