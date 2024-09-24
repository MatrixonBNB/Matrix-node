module EthscriptionEVMConverter
  extend ActiveSupport::Concern
  include Memery
  
  class FunctionMissing < StandardError; end
  class InvalidArgValue < StandardError; end
  class InvalidNumberOfArgs < StandardError; end
  class ContractMissing < StandardError; end
  
  included do
    delegate :local_from_predeploy, to: :PredeployManager
    delegate :get_contract_from_predeploy_info, to: :PredeployManager
    delegate :predeploy_to_local_map, to: :PredeployManager
    delegate :convert_args, to: :class
    delegate :normalize_args, to: :class
    delegate :normalize_arg_value, to: :class
    delegate :real_withdrawal_id, to: :class
    delegate :calculate_to_address, to: :class
    delegate :get_implementation, to: :class
    delegate :validate_import?, to: :class
    delegate :skip_import_validation?, to: :class
    delegate :is_smart_contract_on_l1?, to: :class
    delegate :alias_address_if_necessary, to: :class
  end
  
  def facet_tx_to
    return if parsed_content['op'] == 'create'
    calculate_to_address(parsed_content['data']['to'])
  rescue ContractMissing => e
    shim_val = "0x00000000000000000000000000000000000000c5"
    
    LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
      legacy_value: parsed_content['data']['to'],
      new_value: shim_val
    )
    
    shim_val
  rescue => e
    binding.irb
    puts JSON.pretty_generate(self.as_json)
    puts JSON.pretty_generate(parsed_content.as_json)
    raise
  end
  
  def facet_tx_input
    content = parsed_content
    data = content['data']
    
    if content['op'] == 'create'
      predeploy_address = "0x" + data['init_code_hash'].last(40)
      
      begin
        contract = get_contract_from_predeploy_info(address: predeploy_address)
      rescue KeyError => e
        if skip_import_validation?
          return predeploy_address
        else
          ap content
          binding.irb
          raise
        end
      end
      
      args = convert_args(contract, 'initialize', data['args'])
      
      initialize_calldata = TransactionHelper.get_function_calldata(
        contract: contract,
        function: 'initialize',
        args: args
      )
      
      proxy_contract = get_contract_from_predeploy_info(name: "ERC1967Proxy")
      
      EVMHelpers.get_deploy_data(
        proxy_contract, [predeploy_address, initialize_calldata]
      )
    elsif content['op'] == 'call'
      clear_caches_if_upgrade!
      
      to_address = calculate_to_address(data['to'])
      
      if data['function'] == 'upgradePairs'
        data['args']['pairs'] = data['args']['pairs'].map do |pair|
          calculate_to_address(pair)
        end
      end
      
      implementation_address = get_implementation(to_address)
      contract = get_contract_from_predeploy_info(address: implementation_address)
      
      unless implementation_address
        if skip_import_validation?
          return "0x" + "0" * 100
        else
          binding.irb
          raise "No implementation address for #{to_address}"
        end
      end
      
      args = convert_args(contract, data['function'], data['args'])
      
      if data['function'] == 'upgradeAndCall'
        new_impl_address = "0x" + args.first.last(40)
        new_contract = get_contract_from_predeploy_info(address: new_impl_address)
        migrationCalldata = JSON.parse(args.last)
        migration_args = convert_args(
          new_contract,
          migrationCalldata['function'],
          migrationCalldata['args']
        )
        
        cooked = TransactionHelper.get_function_calldata(
          contract: new_contract,
          function: migrationCalldata['function'],
          args: migration_args
        )
        
        args[1] = ''
        
        args[2] = cooked
      elsif data['function'] == 'setMetadataRenderer'
        begin
          metadata_calldata = JSON.parse(data['args'].is_a?(Array) ? data['args'].last : data['args']['data'])
        rescue JSON::ParserError => e
          raise unless skip_import_validation?
          metadata_calldata = {"function" => "", "args" => {}}
        end
        
        target_contract_name = if metadata_calldata['args'].keys == ['info']
          "EditionMetadataRendererV3f8"
        else
          "TokenUpgradeRendererVbf5"
        end
        
        target_contract = get_contract_from_predeploy_info(name: target_contract_name)
        
        metadata_args = convert_args(
          target_contract,
          metadata_calldata['function'],
          metadata_calldata['args']
        )
        
        cooked_metadata = TransactionHelper.get_function_calldata(
          contract: target_contract,
          function: metadata_calldata['function'],
          args: metadata_args.map(&:to_h)
        )
        
        args[1] = cooked_metadata.hex_to_bytes
      elsif data['function'] == 'bridgeAndCall'
        base64_input = data['args'].is_a?(Hash) ? data['args']['base64Calldata'] : data['args'].last
        
        if base64_input.nil? && skip_import_validation?
          raise InvalidArgValue, "Invalid base64 input"
        end
        
        decoded_input = Base64.strict_decode64(base64_input)
        
        to_address = calculate_to_address(data['args'].is_a?(Hash) ? data['args']['addressToCall'] : data['args'].third)
        implementation_address = get_implementation(to_address)
        sub_contract = get_contract_from_predeploy_info(address: implementation_address)
        
        bridge_calldata = begin
          json_input = JSON.parse(decoded_input)
          
          bridge_args = convert_args(
            sub_contract,
            json_input['function'],
            json_input['args']
          )
          
          TransactionHelper.get_function_calldata(
            contract: sub_contract,
            function: json_input['function'],
            args: bridge_args
          )
        rescue JSON::ParserError => e
          "__invalidJSON__: #{e.message}".bytes_to_hex
        end
                
        encoded_calldata = Base64.strict_encode64(bridge_calldata.hex_to_bytes)
        args[3] = encoded_calldata
      elsif data['function'] == 'callBuddyForUser'
        input = data['args'].is_a?(Hash) ? data['args']['calldata'] : data['args'].last
        decoded_input = input
        
        to_address = calculate_to_address(data['args'].is_a?(Hash) ? data['args']['addressToCall'] : data['args'].second)
        implementation_address = get_implementation(to_address)
        sub_contract = get_contract_from_predeploy_info(address: implementation_address)
        
        factory_calldata = begin
          json_input = JSON.parse(decoded_input)
          
          function = json_input.is_a?(Hash) ? json_input['function'] : json_input.first
          function_args = json_input.is_a?(Hash) ? json_input['args'] : json_input[1..-1]
          
          buddy_args = convert_args(
            sub_contract,
            function,
            function_args
          )
          
          TransactionHelper.get_function_calldata(
            contract: sub_contract,
            function: function,
            args: buddy_args
          )
        rescue JSON::ParserError => e
          "__invalidJSON__: #{e.message}".bytes_to_hex
        end
        
        args[2] = factory_calldata.hex_to_bin
      elsif data['function'] == 'bridgeOut' && contract.name == "ERC20BridgeFactoryVce0"
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
        contract: contract,
        function: data['function'],
        args: args
      )
    else
      raise "Unsupported operation: #{content['op']}"
    end
  rescue FunctionMissing, InvalidArgValue, InvalidNumberOfArgs, Eth::Abi::EncodingError, Eth::Abi::ValueOutOfBounds => e
    message = "Invalid function call: #{e.message}"
    message.bytes_to_hex
  rescue ContractMissing => e
    data['to']
  rescue KeyError => e
    if skip_import_validation?
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

  class_methods do
    include Memery
    
    def validate_import?
      ChainIdManager.on_mainnet?
    end
    
    def skip_import_validation?
      !validate_import?
    end
    
    def get_implementation(to_address)
      TransactionHelper.static_call(
        # Every contract has this function so the choice of EtherBridgeV064 is arbitrary
        contract: PredeployManager.get_contract_from_predeploy_info(name: "EtherBridgeV064"),
        address: to_address,
        function: 'getImplementation',
        args: []
      ).freeze
    end
    memoize :get_implementation
    
    def calculate_to_address(legacy_to)
      legacy_to = legacy_to.downcase
      
      unless LegacyMigrationDataGenerator.instance.current_import_block_number
        return lookup_new_value(legacy_to)
      end
      
      LegacyMigrationDataGenerator.instance.imported_facet_transaction_receipts.each do |receipt|
        if receipt.legacy_contract_address_map.key?(legacy_to)
          new_to = receipt.legacy_contract_address_map[legacy_to]
          
          LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
            legacy_value: legacy_to,
            new_value: new_to
          )
          
          return new_to
        end
      end  
      
      deploy_receipt = FacetTransactionReceipt.find_by("legacy_contract_address_map ? :legacy_to", legacy_to: legacy_to)
      
      unless deploy_receipt
        raise ContractMissing, "Contract #{legacy_to} not found"
      end
      
      new_to = deploy_receipt.legacy_contract_address_map[legacy_to]
      
      LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
        legacy_value: legacy_to,
        new_value: new_to
      )
      
      new_to
    end
    memoize :calculate_to_address
    
    def safe_calculate_to_address(arg)
      mapped = Ethscription.calculate_to_address(arg)
    rescue EthscriptionEVMConverter::ContractMissing, LegacyValueMapping::NoMappingSource
      arg
    end
    
    def convert_args(contract, function_name, args)
      contract_name = contract.name
      function = contract.functions.find { |f| f.name == function_name }
      
      unless function
        current_suffix = contract_name.last(3)
        current_artifact = LegacyContractArtifact.find_by_suffix(current_suffix)
        
        next_artifact = LegacyContractArtifact.find_next_artifact(current_artifact)
        if next_artifact
          next_artifact_suffix = next_artifact.init_code_hash.last(3)
        
          next_artifact_name = contract_name.gsub(current_suffix, next_artifact_suffix)
          
          contract = PredeployManager.get_contract_from_predeploy_info(name: next_artifact_name)
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
      if skip_import_validation?
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
    memoize :normalize_args
    
    def normalize_arg_value(arg_value, input)
      if input.respond_to?(:parsed_type)
        type = input.parsed_type
      else
        type = input
      end
      
      if arg_value.is_a?(String) && type.base_type == "uint" || type.base_type == "int"
        base = arg_value.start_with?('0x') ? 16 : 10
        Integer(arg_value, base)
      elsif arg_value.is_a?(String) && type.base_type == "address"
        arg_value = arg_value.downcase
        
        unless arg_value.match?(/\A0x[0-9a-f]{40}\z/)
          raise InvalidArgValue, "Invalid address: #{arg_value.inspect}!"
        end
        
        alias_address_if_necessary(safe_calculate_to_address(arg_value))
      elsif arg_value.is_a?(Array)
        arg_value.map do |val|
          normalize_arg_value(val, type.nested_sub)
        end
      else
        arg_value
      end
    end
    memoize :normalize_arg_value
    
    def lookup_new_value(legacy_value)
      new_value = LegacyValueMapping.lookup(legacy_value)
      
      if new_value == "0x00000000000000000000000000000000000000c5"
        raise ContractMissing, "Contract #{legacy_value} not found"
      end
      
      if new_value == "0x" + "0" * 62 + "c5"
        raise InvalidArgValue, "Withdrawal ID not found: #{legacy_value}"
      end
      
      new_value
    end
    memoize :lookup_new_value
    
    def real_withdrawal_id(user_withdrawal_id)
      unless LegacyMigrationDataGenerator.instance.current_import_block_number
        return lookup_new_value(user_withdrawal_id)
      end
      
      # Check in-memory cache first
      transaction = LegacyMigrationDataGenerator.instance.imported_facet_transactions.find { |tx| tx.eth_transaction_hash == user_withdrawal_id }
      
      if transaction
        receipt = LegacyMigrationDataGenerator.instance.imported_facet_transaction_receipts.find { |r| r.transaction_hash == transaction.tx_hash }
      else
        # Fallback to database query
        transaction = FacetTransaction.find_by(eth_transaction_hash: user_withdrawal_id)
        if transaction
          receipt = transaction.facet_transaction_receipt
        else
          LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
            legacy_value: user_withdrawal_id,
            new_value: "0x" + "0" * 62 + "c5",
          )
          
          raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
        end
      end
      
      unless receipt
        LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
          legacy_value: user_withdrawal_id,
          new_value: "0x" + "0" * 62 + "c5",
        )
        
        raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
      end
      
      if receipt.status == 0
        LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
          legacy_value: user_withdrawal_id,
          new_value: user_withdrawal_id,
        )
        
        return user_withdrawal_id
      end
      
      new_withdrawal_id = receipt.decoded_logs.
        detect { |i| i['event'] == 'InitiateWithdrawal' }['data']['withdrawalId']
      
      LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
        legacy_value: user_withdrawal_id,
        new_value: new_withdrawal_id,
      )
      
      new_withdrawal_id
    rescue ActiveRecord::RecordNotFound => e
      LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
        legacy_value: user_withdrawal_id,
        new_value: "0x" + "0" * 62 + "c5",
      )
      
      raise InvalidArgValue, "Withdrawal ID not found: #{user_withdrawal_id}"
    end
    memoize :real_withdrawal_id
    
    def is_smart_contract_on_l1?(address)
      unless address.match?(/\A0x[0-9a-f]{40}\z/i)
        return false
      end
      
      puts "is_smart_contract_on_l1? #{address}"
      
      LegacyMigrationDataGenerator.instance.ethereum_client.get_code_at_address(address) != "0x"
    end
    memoize :is_smart_contract_on_l1?
    
    def alias_address_if_necessary(address)
      hashed_address = Eth::Util.keccak256(address.hex_to_bytes).bytes_to_hex

      unless LegacyMigrationDataGenerator.instance.current_import_block_number
        return lookup_new_value(hashed_address)
      end
      
      aliased_address = if is_smart_contract_on_l1?(address)
        AddressAliasHelper.apply_l1_to_l2_alias(address)
      else
        address
      end
      
      LegacyMigrationDataGenerator.instance.add_legacy_value_mapping_item(
        legacy_value: hashed_address,
        new_value: aliased_address,
      )
      
      aliased_address
    end
    memoize :alias_address_if_necessary
  end
end
