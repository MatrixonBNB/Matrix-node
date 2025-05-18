module EthRbExtensions
  ::Eth::Contract.class_eval do
    attr_accessor :bin_runtime
    
    def init_code_hash
      @init_code_hash ||= ByteString.from_hex(bin).keccak256.to_hex
    end
    
    def function_hash
      @function_hash = functions.each_with_object({}) do |function, hash|
        hash[function.name] = function
      end
      # binding.pry
      
      constructor = ::Eth::Contract::Function.new({
        name: 'constructor',
        inputs: [],
        outputs: [],
        stateMutability: 'nonpayable',
        type: 'function'
      }.stringify_keys)
      
      constructor.inputs = constructor_inputs
      @function_hash['constructor'] = constructor
      
      @function_hash
    end
    
    def decode_call_data(calldata)
      # Extract the function signature (first 4 bytes)
      function_signature = calldata[0, 10]
      
      # Find the function by its signature hash
      function = functions.find { |f| f.signature == function_signature[2..9] }
      raise "Function not found for signature: #{function_signature}" unless function
      
      # Remove the function signature from the calldata
      encoded_args = calldata[10..-1]
      
      # Decode the arguments using the ABI types
      types = function.inputs.map(&:parsed_type)
      decoded_args = Eth::Abi.decode(types, Eth::Util.hex_to_bin(encoded_args))
      
      # Map the decoded values back to their respective function inputs
      function.inputs.each_with_index.map do |input, idx|
        [input.name, decoded_args[idx]]
      end.to_h
    rescue Eth::Abi::DecodingError, Eth::Abi::ValueOutOfBounds => e
      # binding.irb
      raise
    rescue => e
      binding.irb
      raise
    end
  end
  
  ::Eth::Contract::Function.class_eval do
    def fix_encodings(arg)
      if arg.is_a?(String)
        arg.b
      elsif arg.is_a?(Array)
        arg.map { |i| fix_encodings(i) }
      elsif arg.is_a?(Hash)
        arg.transform_values { |v| fix_encodings(v) }
      else
        arg
      end
    end
    
    def get_call_data(*args)
      types = inputs.map(&:parsed_type)
      
      args = fix_encodings(args)
      args = normalize_args(args, types)
      
      encoded_str = Eth::Util.bin_to_hex(Eth::Abi.encode(types, args))
      
      if name == 'constructor'
        encoded_str
      else
        Eth::Util.prefix_hex(signature + (encoded_str.empty? ? "0" * 64 : encoded_str))
      end
    rescue Eth::Abi::EncodingError, Eth::Abi::ValueOutOfBounds => e
      puts "Error in get_call_data: #{e.message.inspect}"
      puts "Types: #{types.inspect}"
      puts "Args: #{args.inspect}"
      
      raise
    rescue => e
      puts "Unexpected error in get_call_data: #{e.message.inspect}"
      puts e.backtrace.join("\n")
      binding.irb
      raise
    end
  
    def normalize_args(args, types)
      args.each_with_index.map do |arg, idx|
        normalize_arg_value(arg, types[idx])
      end
    end
    
    def normalize_arg_value(arg_value, type)
      if arg_value.nil? && type.base_type == "address"
        "0x0000000000000000000000000000000000000000"
      elsif arg_value.is_a?(String)
        if type.base_type == "uint" || type.base_type == "int"
          base = arg_value.start_with?('0x') ? 16 : 10
          Integer(arg_value, base)
        elsif arg_value.start_with?("0x") && type.base_type != "string"
          Eth::Util.hex_to_bin(arg_value)
        else
          arg_value
        end
      elsif arg_value.is_a?(Float)
        raise Ethscription::InvalidArgValue, "Float value not supported for type: #{type.inspect}"
      elsif arg_value.is_a?(Hash) && type.base_type == "tuple"
        type.components.each_with_object({}) do |c, normalized_hash|
          normalized_hash[c.name] = normalize_arg_value(arg_value[c.name], c)
        end
      elsif arg_value.is_a?(Array) && type.dimensions.any?
        arg_value.map { |v| normalize_arg_value(v, type.nested_sub) }
      else
        arg_value
      end
    end

    def parse_result(result)
      return nil if result == "0x"
      
      # output_types = outputs.map(&:type)
      output_types = outputs.map do |i|
        i.instance_variable_get(:@type).tap do |j|
          comps = j.instance_variable_get(:@components)
          
          j.instance_variable_set(:@components, comps || [])
        end
      end
      decoded_result = Eth::Abi.decode(output_types, result)

      if outputs.size == 1
        return decoded_result.first
      end
      
      # Check if all outputs have names
      if outputs.all? { |output| output.name.present? }
        # Create a hash with output names as keys
        result_hash = {}.with_indifferent_access
        outputs.each_with_index do |output, index|
          result_hash[output.name] = decoded_result[index]
        end
        result_hash
      else
        decoded_result
      end
    end
  end
  
  ::Eth::Contract::Event.class_eval do
    def decode_log(log, abi)
      # raise "Invalid log address" unless log["address"] == @address

      # Decode the topics and data
      topics = log["topics"]
      data = log["data"]

      # Check if the log matches the event signature
      raise "Invalid log signature" unless topics[0] == "0x#{@signature}"

      # Find the event in the ABI to get indexed information
      event_abi = abi.find { |e| e["name"] == @name && e["type"] == "event" }
      raise "Event ABI not found" unless event_abi

      # Separate indexed and non-indexed inputs
      indexed_inputs = event_abi["inputs"].select { |input| input["indexed"] }
      non_indexed_inputs = event_abi["inputs"].reject { |input| input["indexed"] }

      # Decode indexed data from topics
      decoded_event = {}
      indexed_inputs.each_with_index do |input, index|
        if input["type"] == "string"
          # For indexed strings, just keep the topic (hash) as-is
          decoded_event[input["name"]] = topics[index + 1]
        else
          value = Eth::Abi.decode([input["type"]], topics[index + 1]).first rescue binding.irb
          value = ByteString.from_bin(value).to_hex if input["type"].starts_with?("bytes")
          decoded_event[input["name"]] = value
        end
      end
      
      # Decode non-indexed data from data field
      unless data == "0x"
        begin
          detailed_types = get_detailed_types(non_indexed_inputs)
          # puts "Detailed types: #{detailed_types.inspect}"
          # puts "Data: #{data}"
          decoded_data = Eth::Abi.decode(detailed_types, Eth::Util.hex_to_bin(data))
          # puts "Decoded data: #{decoded_data.inspect}"
        rescue => e
          puts "Error in decode_log: #{e.message}"
          puts "Detailed types: #{detailed_types.inspect}"
          puts "Data: #{data}"
          puts e.backtrace.join("\n")
          binding.irb
          raise
        end
        non_indexed_inputs.each_with_index do |input, index|
          value = decoded_data[index]
          value = process_decoded_value(value, input["type"])
          decoded_event[input["name"]] = value
        end
      end
    
      decoded_event.with_indifferent_access
    end
    
    def get_detailed_types(inputs)
      inputs.map do |input|
        if input["type"] == "tuple"
          Eth::Abi::Type.parse(input["type"], input["components"])
        else
          Eth::Abi::Type.parse(input["type"])
        end
      end
    end
    
    def process_decoded_value(value, type)
      if type.start_with?("tuple")
        value.transform_values do |v|
          v.is_a?(String) ? v.force_encoding("utf-8") : v
        end
      elsif type.start_with?("bytes")
        ByteString.from_bin(value).to_hex
      elsif type == "string"
        value.force_encoding("utf-8")
      else
        value
      end
    end
  end

  ::Eth::Contract.class_eval do
    class ::Eth::Contract::UnknownEvent < StandardError; end
    
    def decode_log(log)
      event = events.find { |e| "0x#{e.signature}" == log["topics"][0] }
      unless event
        raise ::Eth::Contract::UnknownEvent, "Event not found for log signature: #{log["topics"].inspect}"
      end

      decoded_event = event.decode_log(log, abi)
      {
        address: log["address"],
        # event: "#{event.name} (#{event.input_types.join(", ")})",
        # name: event.name,
        event: event.name,
        data: decoded_event,
        blockNumber: log["blockNumber"],
        transactionHash: log["transactionHash"],
        transactionIndex: log["transactionIndex"],
        blockHash: log["blockHash"],
        logIndex: log["logIndex"],
        removed: log["removed"]
      }.with_indifferent_access
    # rescue => e
    #   binding.irb
    #   raise
    end

    def self.decode_function_inputs(contract_address, input_data)
      implementation_address = Ethscription.get_implementation(contract_address)
      implementation_name = Ethscription.local_from_predeploy(implementation_address)
      begin
        contract = PredeployManager.get_contract_from_predeploy_info(name: implementation_name)
      rescue KeyError
        contract = EVMHelpers.compile_contract(implementation_name)
      end

      contract.parent.decode_function_inputs(input_data)
    end

    def decode_function_inputs(input_data)
      # Remove '0x' prefix if present
      input_data = input_data.gsub(/^0x/, '')

      # Function selector (first 4 bytes)
      function_selector = input_data[0...8]

      # Find the function by its signature
      function = functions.find { |f| f.signature == function_selector }
      raise "Function not found for selector: 0x#{function_selector}" unless function

      # Remaining data
      data = input_data[8..]

      # Convert hex string to binary data
      binary_data = [data].pack('H*')

      # Get input types from function
      input_types = function.inputs

      # Decode the input data
      decoded_inputs = {}
      begin
        detailed_types = get_detailed_types(input_types)
        puts "Function: #{function.name}"
        puts "Detailed types: #{detailed_types.inspect}"
        puts "Data: #{data}"
        decoded_data = Eth::Abi.decode(detailed_types, binary_data)
        puts "Decoded data: #{decoded_data.inspect}"

        input_types.each_with_index do |input, index|
          value = decoded_data[index]
          value = process_decoded_value(value, input.type)
          decoded_inputs[input.name] = value
        end
      rescue => e
        puts "Error in decode_function_inputs: #{e.message}"
        puts "Function: #{function.name}"
        puts "Detailed types: #{detailed_types.inspect}"
        puts "Data: #{data}"
        puts e.backtrace.join("\n")
        binding.irb
        raise
      end

      {
        function: function.name,
        inputs: decoded_inputs
      }
    end

    def get_detailed_types(inputs)
      inputs.map do |input|
        if input.type == "tuple"
          Eth::Abi::Type.parse(input.type, input.components)
        else
          Eth::Abi::Type.parse(input.type)
        end
      end
    end

    def process_decoded_value(value, type)
      if type.start_with?("tuple")
        value.transform_values do |v|
          v.is_a?(String) ? v.force_encoding("utf-8") : v
        end
      elsif type.start_with?("bytes")
        ByteString.from_bin(value).to_hex
      elsif type == "string"
        value.force_encoding("utf-8")
      else
        value
      end
    end
  end
end
