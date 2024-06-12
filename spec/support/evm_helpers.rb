module EvmHelpers
  def get_contract(contract_path, address)
    contract_name = contract_path.split('/').last
    contract_file = Rails.root.join('lib', 'solidity', "#{contract_path}.sol")
    contract_compiled = SolidityCompiler.compile(contract_file)
    contract_abi = contract_compiled[contract_name]['abi']
    Eth::Contract.from_abi(name: contract_name, address: address.to_s, abi: contract_abi)
  end
  
  def compile_contract(contract_path)
    contract_name = contract_path.split('/').last
    contract_file = Rails.root.join('lib', 'solidity', "#{contract_path}.sol")
    
    contract_compiled = SolidityCompiler.compile(contract_file)
    contract_bytecode = contract_compiled[contract_name]['bytecode']
    contract_abi = contract_compiled[contract_name]['abi']
    contract = Eth::Contract.from_bin(name: contract_name, bin: contract_bytecode, abi: contract_abi)

    encoded_constructor_params = contract.parent.function_hash['constructor'].get_call_data(*constructor_args)
    deploy_data = contract_bytecode + encoded_constructor_params

    Utils.unprefixed_hex_to_bytes(deploy_data)
  end
  
  def get_deploy_data(contract_path, constructor_args)
    contract_name = contract_path.split('/').last
    contract_file = Rails.root.join('lib', 'solidity', "#{contract_path}.sol")
    
    contract_compiled = SolidityCompiler.compile(contract_file)
    contract_bytecode = contract_compiled[contract_name]['bytecode']
    contract_abi = contract_compiled[contract_name]['abi']
    contract = Eth::Contract.from_bin(name: contract_name, bin: contract_bytecode, abi: contract_abi)

    encoded_constructor_params = contract.parent.function_hash['constructor'].get_call_data(*constructor_args)
    deploy_data = contract_bytecode + encoded_constructor_params
  end
  
  def deploy_contract(evm, contract_path, constructor_args, caller:, gas_limit: 10_000_000)
    deploy_data = get_deploy_data(contract_path, constructor_args)

    deploy_result = evm.run_call(EVMRunCallOpts.new(
      gas_price: 1,
      caller: caller.is_a?(Address) ? caller : Address.from_string(caller),
      value: 0,
      data: [deploy_data].pack('H*').unpack('C*'),
      gas_limit: gas_limit,
    ))

    expect(deploy_result[:exec_result][:exception_error]).to be_nil
    
    evm.journal.cleanup()
    
    deploy_result[:created_address]
  end
  
  def send_transaction_and_expect_success(
    evm,
    contract_name:,
    function:,
    address:,
    args: [],
    caller:,
    value: 0,
    gas_price: 0,
    gas_limit: 30e16.to_i
  )
    contract = get_contract(contract_name, address)
    function = contract.parent.function_hash[function]
    
    args = args.map { |arg| arg.is_a?(Address) ? arg.to_s : arg }
    data = function.get_call_data(*args)
    
    result = evm.run_call(EVMRunCallOpts.new(
      gas_price: gas_price,
      to: Address.from_string(contract.address),
      caller: caller.is_a?(Address) ? caller : Address.from_string(caller),
      value: value,
      data: Utils.hex_to_bytes(data),
      gas_limit: gas_limit,
    ))
    
    if result[:exec_result][:exception_error]
      error_message = extract_revert_reason(result[:exec_result][:return_value])
      raise "Transaction reverted with error: #{error_message}"
    end
    
    expect(result[:exec_result][:exception_error]).to be_nil

    evm.journal.cleanup()
    
    result
  end
  
  def extract_revert_reason(return_value)
    return_value_hex = Utils.bytes_to_hex(return_value.presence || [])
    
    if return_value_hex.start_with?('0x08c379a0') # Function selector for Error(string)
      error_data = return_value_hex[10..-1] # Remove function selector
      error_message = Eth::Abi.decode(['string'], "0x" + error_data).first
      error_message
    else
      'Unknown error'
    end
  end
end
