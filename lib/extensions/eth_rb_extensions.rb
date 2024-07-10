module EthRbExtensions
  ::Eth::Contract.class_eval do
    attr_accessor :bin_runtime
    
    def init_code_hash
      @init_code_hash ||= Eth::Util.keccak256(bin.hex_to_bytes).bytes_to_hex
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
  end
  
  ::Eth::Contract::Function.class_eval do
    def get_call_data(*args)
      types = inputs.map(&:parsed_type)
      
      args = args.map{|i| i.is_a?(String) ? i.b : i}
      args = normalize_args(args, inputs)
      
      encoded_str = Eth::Util.bin_to_hex(Eth::Abi.encode(types, args))
      
      if name == 'constructor'
        encoded_str
      else
        Eth::Util.prefix_hex(signature + (encoded_str.empty? ? "0" * 64 : encoded_str))
      end
    rescue => e
      # binding.irb
      raise
    end
    
    def normalize_args(args, inputs)
      args.each_with_index.map do |arg, idx|
        input = inputs[idx]
        normalize_arg_value(arg, input)
      end
    end
    
    def normalize_arg_value(arg_value, input)
      if arg_value.is_a?(String) && arg_value.starts_with?("0x") && !input.type.starts_with?('string')
        arg_value.hex_to_bytes
      elsif arg_value.is_a?(Array)
        arg_value.map { |val| normalize_arg_value(val, input) }
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
        decoded_event[input["name"]] = Eth::Abi.decode([input["type"]], topics[index + 1]).first
      end

      # Decode non-indexed data from data field
      unless data == "0x"
        decoded_data = Eth::Abi.decode(non_indexed_inputs.map { |input| input["type"] }, data)
        non_indexed_inputs.each_with_index do |input, index|
          decoded_event[input["name"]] = decoded_data[index]
        end
      end

      decoded_event.with_indifferent_access
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
    end
  end
end
