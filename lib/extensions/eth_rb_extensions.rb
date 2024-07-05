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
      output_types = outputs.map(&:type)
      return nil if result == "0x"
      Eth::Abi.decode(output_types, result)
    end
  end
end
