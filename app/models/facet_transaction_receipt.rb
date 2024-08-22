class FacetTransactionReceipt < ApplicationRecord
  include Memery
  
  belongs_to :facet_transaction, primary_key: :tx_hash, foreign_key: :transaction_hash
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
  
  attr_accessor :legacy_receipt
  
  def set_legacy_contract_address_map
    unless legacy_receipt
      self.legacy_contract_address_map[calculate_legacy_contract_address] = contract_address
      self.legacy_contract_address_map.reject! { |k, v| k.nil? || v.nil? }
      
      self.legacy_contract_address_map.each do |legacy_address, new_address|
        EthscriptionsImporter.instance.add_legacy_value_mapping_item(
          legacy_value: legacy_address,
          new_value: new_address
        )
      end
      
      return
    end
  
    self.legacy_contract_address_map[legacy_receipt.created_contract_address] = contract_address
  
    update_legacy_contract_address_map('PairCreated', 'pair')
    update_legacy_contract_address_map('BridgeCreated', 'newBridge')
    update_legacy_contract_address_map('BuddyCreated', 'buddy')
  
    self.legacy_contract_address_map.reject! { |k, v| k.nil? || v.nil? }
    
    # puts JSON.pretty_generate(self.as_json)
    # puts JSON.pretty_generate(legacy_receipt.as_json)
    
    self.legacy_contract_address_map.each do |legacy_address, new_address|
      EthscriptionsImporter.instance.add_legacy_value_mapping_item(
        legacy_value: legacy_address,
        new_value: new_address
      )
    end
  end
  
  def update_real_withdrawal_id
    initiate_event = decoded_legacy_logs.detect { |i| i['event'] == 'InitiateWithdrawal' }
    
    return unless initiate_event
    
    withdrawal_id = initiate_event['data']['withdrawalId']
    
    EthscriptionsImporter.instance.add_legacy_value_mapping_item(
      legacy_value: legacy_receipt.transaction_hash,
      new_value: withdrawal_id
    )
  rescue => e
    binding.irb
    raise
  end
  
  def update_legacy_contract_address_map(event_name, key_name)
    our_event = decoded_legacy_logs.detect { |log| log['event'] == event_name }
  
    their_event = legacy_receipt.logs.detect { |i| i['event'] == event_name }
    
    if (our_event.nil? && their_event.nil?) || (legacy_receipt.status == 'failure' && status == 0)
      return
    end
    
    if (our_event.nil? && their_event.nil?) || (ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia" && status == 0)
      return
    end
    
    unless our_event.present? && their_event.present?
      return if ENV.fetch('ETHEREUM_NETWORK') == "eth-sepolia"
      binding.irb
      raise "One of the events is missing"
    end
  
    our_data = our_event['data'][key_name]
    their_data = their_event['data'][key_name]
  
    unless our_data
      binding.irb
      raise "Key '#{key_name}' not found in our event data for #{event_name}"
    end
  
    unless their_data
      binding.irb
      raise "Key '#{key_name}' not found in their event data for #{event_name}"
    end
  
    self.legacy_contract_address_map[their_data] = our_data
  end

  # def set_legacy_contract_address_map
  #   unless legacy_receipt
  #     self.legacy_contract_address_map[calculate_legacy_contract_address] = contract_address
  #     self.legacy_contract_address_map.compact!
  #     return
  #   end
    
  #   self.legacy_contract_address_map[legacy_receipt.created_contract_address] = contract_address
    
  #   our_pair_created = decoded_legacy_logs.detect do |log|
  #     log['event'] == 'PairCreated'
  #   end
    
  #   if our_pair_created
  #     their_pair_created = legacy_receipt.logs.detect{|i| i['event'] == 'PairCreated'}
      
  #     if their_pair_created
  #       self.legacy_contract_address_map[their_pair_created['data']['pair']] = our_pair_created['data']['pair']
  #     end
  #   end
    
  #   self.legacy_contract_address_map.compact!
  # end
  
  def trace
    # t = process_trace(GethDriver.trace_transaction(transaction_hash))
    # t = test_trace
    t = GethDriver.trace_transaction(transaction_hash)
    
    decoder = TransactionDecoder.new(t)
    decoder.decode_trace
  end
  
  def process_trace(trace)
    trace['calls'].each do |call|
      process_call(call)
    end
  end
  
  def process_call(call)
    if call['to'] == '0x000000000000000000636f6e736f6c652e6c6f67'
      data = call['input'][10..-1]
      decoded_data = Eth::Abi.decode(['string'], [data].pack('H*')) rescue [data]
      decoded_log = decoded_data.first
      call['console.log'] = decoded_log
      call.delete('input')
      call.delete('gas')
      call.delete('gasUsed')
      call.delete('to')
      call.delete('type')
    end
  
    # Recursively process nested calls
    if call['calls']
      call['calls'].each do |sub_call|
        process_call(sub_call)
      end
    end
  end
  
  def decoded_legacy_logs
    logs.map do |log|
      implementation_address = Ethscription.get_implementation(log['address'])
      implementation_name = Ethscription.local_from_predeploy(implementation_address)
      impl = EVMHelpers.compile_contract(implementation_name)
  
      begin
        impl.parent.decode_log(log)
      rescue Eth::Contract::UnknownEvent => e
        # If unknown event, try all contracts in the legacy directory
        legacy_dir = Rails.root.join('lib', 'solidity', 'legacy')
        legacy_files = Dir.glob(legacy_dir.join('*.sol'))
  
        legacy_files.sort_by! { |file| File.basename(file, '.sol') == 'ERC1967Proxy' ? 0 : 1 }
        
        decoded = nil
        legacy_files.each do |file|
          contract_name = File.basename(file, '.sol')
          begin
            impl = EVMHelpers.compile_contract("legacy/#{contract_name}")
            decoded = impl.parent.decode_log(log)
            break if decoded
          rescue Eth::Contract::UnknownEvent
            next
          rescue => e
            Rails.logger.error("Error decoding log with contract #{contract_name}: #{e.message}")
            binding.irb
            raise
          end
        end
  
        raise Eth::Contract::UnknownEvent, "Unknown event for log: #{log}" unless decoded
        decoded
      rescue => e
        # Log the error and raise
        Rails.logger.error("Error decoding log: #{e.message}")
        binding.irb
        raise
      end
    end
  end
  memoize :decoded_legacy_logs
  
  def calculate_legacy_contract_address
    return unless contract_address
    
    current_nonce = FacetTransactionReceipt
      .where(from_address: from_address)
      .where('block_number < ? OR (block_number = ? AND transaction_index < ?)', block_number, block_number, transaction_index)
      .count
    
    rlp_encoded = Eth::Rlp.encode([
      Integer(from_address, 16),
      current_nonce,
      "facet"
    ])
    
    hash = Eth::Util.keccak256(rlp_encoded).bytes_to_unprefixed_hex
    "0x" + hash.last(40)
  end
  
  class TransactionDecoder
    def initialize(trace)
      @trace = trace
    end
  
    def decode_trace
      return @trace unless @trace['calls']
      
      decode_calls(@trace['calls'])
    end
  
    private
  
    def decode_calls(calls, delegate_call_data = {})
      calls.each do |call|
        if call["type"] == "DELEGATECALL"
          to_address = call["to"]
          contract_name = Ethscription.local_from_predeploy(to_address)
          abi = get_abi(contract_name)
          function_name, decoded_inputs, decoded_outputs = decode_function_input(call, abi)
          call["function_name"] = function_name
          call["inputs"] = decoded_inputs
          call["outputs"] = decoded_outputs
          # call.delete("input")
          # call.delete("output") if decoded_outputs
  
          # Store the decoded values for DELEGATECALL
          delegate_call_data[function_signature(call["input"])] = { inputs: decoded_inputs, outputs: decoded_outputs } if call["input"]
        # elsif ["CALL", "STATICCALL"].include?(call["type"])
        #   # Check if the function signature matches any in the delegate_call_data
        #   signature = function_signature(call["input"]) if call["input"]
        #   if signature && delegate_call_data.key?(signature)
        #     call["inputs"] = delegate_call_data[signature][:inputs]
        #     call["outputs"] = delegate_call_data[signature][:outputs]
        #     call['error'] = delegate_call_data[signature][:error]
        #     call['function_name'] = delegate_call_data[signature][:function_name]
        #     # call.delete("input")
        #     # call.delete("output") if delegate_call_data[signature][:outputs]
        #   end
        end
  
        # Recursively decode nested calls
        decode_calls(call["calls"], delegate_call_data) if call["calls"]
  
        # Reorder keys to ensure "calls" is at the end
        reorder_keys(call)
      end
    rescue => e
      binding.irb
      raise
    end
  
    def get_abi(contract_name)
      EVMHelpers.compile_contract(contract_name).abi
    end
  
    def decode_function_input(call, abi)
      input_data = call["input"]
      output_data = call["output"]
      function_signature = input_data[0, 10] if input_data
      function_abi = abi.find { |f| f["type"] == "function" && Eth::Util.keccak256(f["name"] + "(" + f["inputs"].map { |i| i["type"] }.join(",") + ")").bytes_to_hex[0, 10] == function_signature } if function_signature
  
      if function_abi
        decoded_inputs = Eth::Abi.decode(function_abi["inputs"].map { |i| i["type"] }, input_data[10..-1])
        decoded_data_inputs = {}
        function_abi["inputs"].each_with_index do |input, index|
          decoded_data_inputs[input['name']] = decoded_inputs[index]
        end
  
        decoded_data_outputs = nil
        if output_data
          if is_error_output?(output_data, abi)
            decoded_data_outputs = decode_error_output(output_data, abi)
          elsif function_abi["outputs"]
            decoded_outputs = Eth::Abi.decode(function_abi["outputs"].map { |o| o["type"] }, output_data)
            decoded_data_outputs = {}
            function_abi["outputs"].each_with_index do |output, index|
              decoded_data_outputs[output['name']] = decoded_outputs[index]
            end
          end
        end
  
        [function_abi["name"], decoded_data_inputs, decoded_data_outputs]
      else
        puts "Function ABI not found for signature: #{function_signature}"
        [nil, {}, nil]
      end
    end
  
    def function_signature(input_data)
      input_data[0, 10] if input_data
    end
  
    def is_error_output?(output_data, abi)
      # Generate error signatures from the ABI
      error_signatures = abi.select { |e| e["type"] == "error" }.map do |error|
        Eth::Util.keccak256(error["name"] + "(" + error["inputs"].map { |i| i["type"] }.join(",") + ")").bytes_to_hex[0, 10]
      end
      error_signatures.include?(output_data[0, 10])
    end
  
    def decode_error_output(output_data, abi)
      # Decode the error output based on the error definitions in the ABI
      error_abi = abi.find { |e| e["type"] == "error" && Eth::Util.keccak256(e["name"] + "(" + e["inputs"].map { |i| i["type"] }.join(",") + ")").bytes_to_hex[0, 10] == output_data[0, 10] }
      if error_abi
        decoded_error = Eth::Abi.decode(error_abi["inputs"].map { |i| i["type"] }, output_data[10..-1])
        decoded_data_error = { "error_name" => error_abi["name"] }
        error_abi["inputs"].each_with_index do |input, index|
          decoded_data_error[input['name']] = decoded_error[index]
        end
        decoded_data_error
      else
        puts "Error ABI not found for signature: #{output_data[0, 10]}"
        nil
      end
    end
  
    def reorder_keys(call)
      reordered_call = call.slice("from", "gas", "gasUsed", "to", "value", "type", "function_name", "input", "inputs", "outputs", "output", "error")
      reordered_call["calls"] = call["calls"] if call["calls"]
      call.replace(reordered_call)
    end
  end
  
  def self.address_mapping_file_path
    prefix = ENV.fetch('ETHEREUM_NETWORK').underscore
    
    Rails.root.join("#{prefix}_legacy_address_mapping.json")
  end
  
  def self.write_legacy_address_mapping(force: false)
    merged_address_map = {}
  
    FacetTransactionReceipt.where("legacy_contract_address_map::text != '{}'").each do |receipt|
      merged_address_map.merge!(receipt.legacy_contract_address_map)
    end
  
    json = JSON.pretty_generate(merged_address_map)
    
    if File.exist?(address_mapping_file_path) && !force
      raise "Address mapping file already exists (pass force: true to overwrite)"
    end
    
    File.write(address_mapping_file_path, json)
  end
  
  def self.cached_legacy_address_mapping
    return @_cached_legacy_address_mapping if defined?(@_cached_legacy_address_mapping)
      
    @_cached_legacy_address_mapping = if File.exist?(address_mapping_file_path)
      JSON.parse(File.read(address_mapping_file_path)).transform_keys(&:downcase).transform_values(&:downcase)
    else
      {}
    end
  end
  
  def self.map_legacy_address(address)
    cached_legacy_address_mapping[address.downcase]
  end
end
