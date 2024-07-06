module EthRbExtensions
  ::Eth::Contract.class_eval do
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
      
      args = args.map do |arg|
        arg.is_a?(String) && arg.starts_with?("0x") ? arg.hex_to_bytes : arg
      end
      
      encoded_str = Eth::Util.bin_to_hex(Eth::Abi.encode(types, args))
      
      if name == 'constructor'
        encoded_str
      else
        Eth::Util.prefix_hex(signature + (encoded_str.empty? ? "0" * 64 : encoded_str))
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
      decoded_result = Eth::Abi.decode(output_types, result) rescue binding.pry

      # Check if all outputs have names
      if outputs.all? { |output| output.name }
        # Create a hash with output names as keys
        result_hash = {}
        outputs.each_with_index do |output, index|
          result_hash[output.name] = decoded_result[index]
        end
        result_hash
      else
        decoded_result
      end
    end
  end
end
