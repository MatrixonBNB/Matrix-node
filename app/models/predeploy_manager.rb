module PredeployManager
  extend self
  include Memery
  
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
        
        deployed_by_contract_prefixes = %w(ERC20Bridge FacetBuddy FacetSwapPair)
        
        if deployed_by_contract_prefixes.any? { |prefix| filename.match(/^#{prefix}V[a-f0-9]{3}$/i) }
          contract = EVMHelpers.compile_contract("legacy/#{filename}")
        
          map["0x" + contract.parent.init_code_hash.last(40)] = filename
        end
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

  def get_code(address)
    local = local_from_predeploy(address)
    contract = EVMHelpers.compile_contract(local)
    raise unless contract.parent.bin_runtime
    unless is_valid_hex?("0x" + contract.parent.bin_runtime)
      binding.irb
      raise
    end
    contract.parent.bin_runtime
  end
  
  def is_valid_hex?(hex)
    hex.match?(/^0x[0-9a-fA-F]+$/) && hex.length.even?
  end
  
  def generate_alloc_for_genesis
    initializable_slot = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132"
    
    max_uint64 = 2 ** 64 - 1

    result = max_uint64 << 1

    hex_result = result.zpad(32).bytes_to_hex
    
    predeploy_to_local_map.map do |address, alloc|
      [
        address,
        {
          "code" => "0x" + get_code(address),
          "balance" => 0,
          "storage" => {
            initializable_slot => hex_result
          }
        }
      ]
    end.to_h
  end
  
  def generate_full_genesis_json(network = ENV.fetch('ETHEREUM_NETWORK'))
    unless ["eth-mainnet", "eth-sepolia"].include?(network)
      raise "Invalid network: #{network}"
    end
    
    config = {
      chainId: FacetTransaction.current_chain_id(network),
      homesteadBlock: 0,
      eip150Block: 0,
      eip155Block: 0,
      eip158Block: 0,
      byzantiumBlock: 0,
      constantinopleBlock: 0,
      petersburgBlock: 0,
      istanbulBlock: 0,
      muirGlacierBlock: 0,
      berlinBlock: 0,
      londonBlock: 0,
      mergeForkBlock: 0,
      mergeNetsplitBlock: 0,
      shanghaiTime: 0,
      cancunTime: cancun_timestamp(network),
      terminalTotalDifficulty: 0,
      terminalTotalDifficultyPassed: true,
      bedrockBlock: 0,
      regolithTime: 0,
      canyonTime: 0,
      ecotoneTime: 0,
      optimism: {
        eip1559Elasticity: 2,
        eip1559Denominator: 8,
        eip1559DenominatorCanyon: 8
      }
    }
    
    timestamp = network == "eth-mainnet" ? 1701353099 : 1706742588
    mix_hash = network == "eth-mainnet" ?
      "0xf9202de594a3697695c54a4ee8a392f686ca1fc26337eb821e4ca6deb71b2dd7" :
      "0xc4b4bbd867f5566c344e8ba74372ca493c91c00bb3e10f85a45bd9e89344a977"
    
    {
      config: config,
      timestamp: "0x#{timestamp.to_s(16)}",
      extraData: "Think outside the block".ljust(32).bytes_to_hex,
      gasLimit: "0x#{300e6.to_i.to_s(16)}",
      difficulty: "0x0",
      mixHash: mix_hash,
      alloc: generate_alloc_for_genesis
    }
  end
  
  def cancun_timestamp(network = ENV.fetch('ETHEREUM_NETWORK'))
    network == "eth-mainnet" ? 1710338135 : 1706655072
  end
  
  def write_genesis_json(clear_cache: true)
    Rails.cache.clear if clear_cache
    MemeryExtensions.clear_all_caches!
    SolidityCompiler.reset_checksum
    SolidityCompiler.compile_all_legacy_files
    
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')
    
    ["eth-mainnet", "eth-sepolia"].each do |network|
      filename = network == "eth-mainnet" ? "facet-mainnet.json" : "facet-sepolia.json"
      genesis_path = File.join(geth_dir, 'facet-chain', filename)

      # Generate the genesis data for the specific network
      genesis_data = generate_full_genesis_json(network)

      # Write the data to the appropriate file
      File.write(genesis_path, JSON.pretty_generate(genesis_data))
      
      puts "Generated #{filename}"
    end
  end
end
