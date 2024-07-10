class Ethscription < ApplicationRecord
  include Memery
  class << self
    include Memery
  end
  
  class FunctionMissing < StandardError; end
  class InvalidArgValue < StandardError; end
  class ContractMissing < StandardError; end
  
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true, autosave: false
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash, optional: true, autosave: false
  has_one :facet_transaction, primary_key: :transaction_hash, foreign_key: :tx_hash
  has_one :facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  has_one :legacy_facet_transaction, primary_key: :transaction_hash, foreign_key: :transaction_hash
  has_one :legacy_facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  delegate :get_code, :local_from_predeploy, :predeploy_to_local_map, to: :class
  
  def content
    content_uri[/.*?,(.*)/, 1]
  end
  
  def block_hash
    block_blockhash
  end
  
  def parsed_content
    JSON.parse(content)
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
  
  def facet_tx_input
    content = parsed_content
    data = content['data']
    
    if content['op'] == 'create'
      predeploy_address = "0x" + data['init_code_hash'].last(40)
      
      contract_name = local_from_predeploy(predeploy_address)
      args = convert_args(contract_name, 'initialize', data['args'])
      
      initialize_calldata = TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: 'initialize',
        args: args
      )
      
      TransactionHelper.get_deploy_data(
        'legacy/ERC1967Proxy', [predeploy_address, initialize_calldata]
      )
    elsif content['op'] == 'call'
      to_address = calculate_to_address(data['to'], block_number)
      
      implementation_address = get_implementation(to_address)
      
      unless implementation_address
        binding.irb
        raise "No implementation address for #{to_address}"
      end
      
      contract_name = local_from_predeploy(implementation_address)
      args = convert_args(contract_name, data['function'], data['args'])
      
      TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: data['function'],
        args: args
      )
    else
      raise "Unsupported operation: #{content['op']}"
    end
  rescue FunctionMissing, InvalidArgValue => e
    data['args'].to_json.bytes_to_hex
  rescue ContractMissing => e
    data['to']
  rescue KeyError => e
    ap content
    binding.irb
    raise
  rescue => e
    binding.irb
    raise
  end
  
  def facet_tx_to
    return if parsed_content['op'] == 'create'
    calculate_to_address(parsed_content['data']['to'], block_number)
  rescue ContractMissing => e
    "0x00000000000000000000000000000000000000c5"
  end
  
  class << self
    def get_implementation(to_address)
      Rails.cache.fetch([to_address, '__getImplementation', Rails.env]) do
        TransactionHelper.static_call(
          contract: 'legacy/ERC1967Proxy',
          address: to_address,
          function: '__getImplementation',
          args: []
        )
      end
    end
    memoize :get_implementation
    
    def calculate_to_address(legacy_to, block_number)
      deploy_receipt = FacetTransactionReceipt.find_by("legacy_contract_address_map ? :legacy_to", legacy_to: legacy_to)
      
      unless deploy_receipt
        raise ContractMissing, "Contract #{legacy_to} not found"
      end
      
      deploy_receipt.legacy_contract_address_map[legacy_to]
    end
    memoize :calculate_to_address
  end
  delegate :calculate_to_address, to: :class
  delegate :get_implementation, to: :class
  
  def self.t
    no_ar_logging; EthBlock.delete_all; reload!; 50.times{EthBlockImporter.import_next_block;}
  end
  
  def convert_args(contract, function_name, args)
    contract = EVMHelpers.compile_contract(contract)
    function = contract.functions.find { |f| f.name == function_name }
    
    unless function
      raise FunctionMissing, "Function #{function_name} not found in #{contract}"
    end
    
    inputs = function.inputs
    
    args = [args] if args.is_a?(String) || args.is_a?(Integer)
    
    if args.is_a?(Hash)
      args_hash = args.with_indifferent_access
      args = inputs.map do |input|
        args_hash[input.name]
      end
    end
    
    args = normalize_args(args, inputs)
    
    args
  rescue ArgumentError => e
    if e.message.include?("invalid value for Integer()")
      raise InvalidArgValue, "Invalid value: #{e.message.split(':').last.strip}"
    else
      raise
    end
  end
  
  def normalize_args(args, inputs)
    args&.each_with_index&.map do |arg_value, idx|
      input = inputs[idx]
      normalize_arg_value(arg_value, input)
    end
  end

  def normalize_arg_value(arg_value, input)
    if arg_value.is_a?(String) && (input.type.starts_with?('uint') || input.type.starts_with?('int'))
      Integer(arg_value, 10)
    elsif arg_value.is_a?(Array)
      arg_value.map do |val|
        normalize_arg_value(val, input)
      end
    else
      arg_value
    end
  end
  
  def self.predeploy_to_local_map
    index_by_real_init_code = [
      "FacetSwapPairV1"
    ]
    
    map = {
      "0x897d289b77c8393783829489b9ab3255c0158064": "EtherBridgeV1",
      "0x137e368f782453e41f622fa8cf68296d04c84c88": "PublicMintERC20V1",
      "0x9dc4e7f596baf4227f919102a7f80523834edb02": "AirdropERC20V1",
      "0xc30f329f29806a5e4db65ee5aa7652826f65bd9d": "EthscriptionERC20BridgeV1",
      "0xdd0b7d9c9c4d8534b384db5339f4a26dffc6e139": "NameRegistryV1",
      "0x0ad9c442bd4eb506447f125b7e71b64e33583e7f": "FacetSwapFactoryV1",
      "0x1f157ea244a08dd78c14ba8faa7280559232b099": "FacetSwapRouterV1",
      "0x00000000000000000000000000000000000000c5": "NonExistentContractShim"
    }.with_indifferent_access
    
    index_by_real_init_code.each do |contract|
      contract = EVMHelpers.compile_contract("legacy/#{contract}")
      map["0x" + contract.parent.init_code_hash.last(40)] = contract.name
    end
    
    map
  end
  
  def self.local_from_predeploy(address)
    name = predeploy_to_local_map.fetch(address.downcase)
    
    "legacy/#{name}"
  end
  
  def self.get_code(address)
    local = local_from_predeploy(address)
    contract = EVMHelpers.compile_contract(local)
    raise unless contract.parent.bin_runtime
    contract.parent.bin_runtime
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
    SolidityCompiler.reset_checksum
    
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')
    genesis_path = File.join(geth_dir, 'facet-chain', 'genesis3.json')

    # Read the existing genesis.json file
    genesis_data = JSON.parse(File.read(genesis_path))

    # Overwrite the "alloc" key with the new allocation
    genesis_data['alloc'] = generate_alloc_for_genesis

    # Write the updated data back to the genesis.json file
    File.write(genesis_path, JSON.pretty_generate(genesis_data))
  end
  
  def self.sample_content
    {
      "op": "create",
      "data": {
        "init_code_hash": "0xbae85b82353ff68e9cee3036897d289b77c8393783829489b9ab3255c0158064",
        "args": {
          "trustedSmartContract": "0xbE73b799BE0b492c36b19bf7a69D4a6b41D90214",
          "name": "Facet Ether",
          "symbol": "FETH"
        },
        "source_code": "pragma(:rubidity, \"1.0.0\")\ncontract(:ERC20, abstract: true) {\n  event(:Transfer, { from: :address, to: :address, amount: :uint256 })\n  event(:Approval, { owner: :address, spender: :address, amount: :uint256 })\n  string(:public, :name)\n  string(:public, :symbol)\n  uint8(:public, :decimals)\n  uint256(:public, :totalSupply)\n  mapping(({ address: :uint256 }), :public, :balanceOf)\n  mapping(({ address: mapping(address: :uint256) }), :public, :allowance)\n  constructor(name: :string, symbol: :string, decimals: :uint8) {\n    s.name=name\n    s.symbol=symbol\n    s.decimals=decimals\n  }\n  function(:approve, { spender: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\n    s.allowance[msg.sender][spender] = amount\n    emit(:Approval, owner: msg.sender, spender: spender, amount: amount)\n    return true\n  }\n  function(:transfer, { to: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\n    require(s.balanceOf[msg.sender] \u003e= amount, \"Insufficient balance\")\n    s.balanceOf[msg.sender] -= amount\n    s.balanceOf[to] += amount\n    emit(:Transfer, from: msg.sender, to: to, amount: amount)\n    return true\n  }\n  function(:transferFrom, { from: :address, to: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\n    allowed = s.allowance[from][msg.sender]\n    require(s.balanceOf[from] \u003e= amount, \"Insufficient balance\")\n    require(allowed \u003e= amount, \"Insufficient allowance\")\n    s.allowance[from][msg.sender] = allowed - amount\n    s.balanceOf[from] -= amount\n    s.balanceOf[to] += amount\n    emit(:Transfer, from: from, to: to, amount: amount)\n    return true\n  }\n  function(:_mint, { to: :address, amount: :uint256 }, :internal, :virtual) {\n    s.totalSupply += amount\n    s.balanceOf[to] += amount\n    emit(:Transfer, from: address(0), to: to, amount: amount)\n  }\n  function(:_burn, { from: :address, amount: :uint256 }, :internal, :virtual) {\n    require(s.balanceOf[from] \u003e= amount, \"Insufficient balance\")\n    s.balanceOf[from] -= amount\n    s.totalSupply -= amount\n    emit(:Transfer, from: from, to: address(0), amount: amount)\n  }\n}\ncontract(:Upgradeable, abstract: true) {\n  address(:public, :upgradeAdmin)\n  event(:ContractUpgraded, { oldHash: :bytes32, newHash: :bytes32 })\n  event(:UpgradeAdminChanged, { newUpgradeAdmin: :address })\n  constructor(upgradeAdmin: :address) {\n    s.upgradeAdmin=upgradeAdmin\n  }\n  function(:setUpgradeAdmin, { newUpgradeAdmin: :address }, :public) {\n    require(msg.sender == s.upgradeAdmin, \"NOT_AUTHORIZED\")\n    s.upgradeAdmin=newUpgradeAdmin\n    emit(:UpgradeAdminChanged, newUpgradeAdmin: newUpgradeAdmin)\n  }\n  function(:upgradeAndCall, { newHash: :bytes32, newSource: :string, migrationCalldata: :string }, :public) {\n    upgrade(newHash: newHash, newSource: newSource)\n    (success, data) = address(this).call(migrationCalldata)\n    require(success, \"Migration failed\")\n  }\n  function(:upgrade, { newHash: :bytes32, newSource: :string }, :public) {\n    currentHash = this.currentInitCodeHash\n    require(msg.sender == s.upgradeAdmin, \"NOT_AUTHORIZED\")\n    this.upgradeImplementation(newHash, newSource)\n    emit(:ContractUpgraded, oldHash: currentHash, newHash: newHash)\n  }\n}\ncontract(:EtherBridge, is: [:ERC20, :Upgradeable], upgradeable: true) {\n  event(:BridgedIn, { to: :address, amount: :uint256 })\n  event(:InitiateWithdrawal, { from: :address, amount: :uint256, withdrawalId: :bytes32 })\n  event(:WithdrawalComplete, { to: :address, amount: :uint256, withdrawalId: :bytes32 })\n  address(:public, :trustedSmartContract)\n  mapping(({ bytes32: :uint256 }), :public, :withdrawalIdAmount)\n  mapping(({ address: :bytes32 }), :public, :userWithdrawalId)\n  constructor(name: :string, symbol: :string, trustedSmartContract: :address) {\n    require(trustedSmartContract != address(0), \"Invalid smart contract\")\n    self.ERC20.constructor(name: name, symbol: symbol, decimals: 18)\n    self.Upgradeable.constructor(upgradeAdmin: msg.sender)\n    s.trustedSmartContract=trustedSmartContract\n  }\n  function(:bridgeIn, { to: :address, amount: :uint256 }, :public) {\n    require(msg.sender == s.trustedSmartContract, \"Only the trusted smart contract can bridge in tokens\")\n    _mint(to: to, amount: amount)\n    emit(:BridgedIn, to: to, amount: amount)\n  }\n  function(:bridgeOut, { amount: :uint256 }, :public) {\n    withdrawalId = tx.current_transaction_hash\n    require(s.userWithdrawalId[msg.sender] == bytes32(0), \"Withdrawal pending\")\n    require(s.withdrawalIdAmount[withdrawalId] == 0, \"Already bridged out\")\n    require(amount \u003e 0, \"Invalid amount\")\n    s.userWithdrawalId[msg.sender] = withdrawalId\n    s.withdrawalIdAmount[withdrawalId] = amount\n    _burn(from: msg.sender, amount: amount)\n    emit(:InitiateWithdrawal, from: msg.sender, amount: amount, withdrawalId: withdrawalId)\n  }\n  function(:markWithdrawalComplete, { to: :address, withdrawalId: :bytes32 }, :public) {\n    require(msg.sender == s.trustedSmartContract, \"Only the trusted smart contract can mark withdrawals as complete\")\n    require(s.userWithdrawalId[to] == withdrawalId, \"Withdrawal id not found\")\n    amount = s.withdrawalIdAmount[withdrawalId]\n    s.withdrawalIdAmount[withdrawalId] = 0\n    s.userWithdrawalId[to] = bytes32(0)\n    emit(:WithdrawalComplete, to: to, amount: amount, withdrawalId: withdrawalId)\n  }\n}\n"
      }
    }.to_json
  end
end
