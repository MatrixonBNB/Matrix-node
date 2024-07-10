module EVMHelpers
  include Memery
  class << self
    include Memery
  end
  extend self
  
  def get_contract(contract_path, address)
    contract_name = contract_path.split('/').last
    contract_file = Rails.root.join('lib', 'solidity', "#{contract_path}.sol")
    contract_compiled = SolidityCompiler.compile(contract_file)
    contract_abi = contract_compiled[contract_name]['abi']
    Eth::Contract.from_abi(name: contract_name, address: address.to_s, abi: contract_abi)
  end

  
  class << self
    def compile_contract(contract_path)
      checksum = SolidityCompiler.directory_checksum
    
      memoized_compile_contract(contract_path, checksum)
    end
    
    def memoized_compile_contract(contract_path, checksum)
      Rails.cache.fetch(['memoized_compile_contract', contract_path, checksum]) do
        contract_name = contract_path.split('/').last
        contract_file = Rails.root.join('lib', 'solidity', "#{contract_path}.sol")
        
        contract_compiled = SolidityCompiler.compile(contract_file)
        contract_bytecode = contract_compiled[contract_name]['bytecode']
        contract_abi = contract_compiled[contract_name]['abi']
        contract_bin_runtime = contract_compiled[contract_name]['bin_runtime']
        contract = Eth::Contract.from_bin(name: contract_name, bin: contract_bytecode, abi: contract_abi)
        contract.parent.bin_runtime = contract_bin_runtime
        contract
      end
    end
    
    memoize :memoized_compile_contract
  end
  delegate :compile_contract, to: EVMHelpers
  
  def proxy_and_implementation_deploy_data(
    proxy_path: 'legacy/EtherBridge',
    implementation_path: 'legacy/EtherBridgeV1',
    init_args: ["name", "symbol", "0xC2172a6315c1D7f6855768F843c420EbB36eDa97", "0xC2172a6315c1D7f6855768F843c420EbB36eDa97"]
  )
    implementation = compile_contract(implementation_path)
    implementation_byte_code = get_deploy_data(implementation_path, [])
    
    implementation_init = implementation.parent.function_hash['initialize'].get_call_data(*init_args)
    
    proxy_deploy_data = get_deploy_data(proxy_path, [implementation_byte_code, implementation_init])
  end
  
  def get_deploy_data(contract_path, constructor_args)
    contract = EVMHelpers.compile_contract(contract_path)

    encoded_constructor_params = contract.parent.function_hash['constructor'].get_call_data(*constructor_args)
    deploy_data = contract.bin + encoded_constructor_params
  rescue => e
    binding.irb
    raise
  end

end
