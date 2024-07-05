class Ethscription < ApplicationRecord
  belongs_to :eth_block, foreign_key: :block_number, primary_key: :block_number, optional: true, autosave: false
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash, optional: true, autosave: false
  has_one :facet_transaction, primary_key: :transaction_hash, foreign_key: :tx_hash
  has_one :facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  has_one :legacy_facet_transaction, primary_key: :transaction_hash, foreign_key: :transaction_hash
  has_one :legacy_facet_transaction_receipt, primary_key: :transaction_hash, foreign_key: :transaction_hash
  
  def content
    content_uri[/.*?,(.*)/, 1]
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
  
  def facet_tx_input
    self.class.content_to_input(content)
  end
  
  def self.content_to_input(content)
    content = JSON.parse(content, object_class: OpenStruct)
    data = content.data
    
    if content.op == 'create'
      predeploy_address = "0x" + data.init_code_hash.last(40)
      
      contract_name = local_from_predeploy(predeploy_address)
      args = convert_args(contract_name, 'initialize', data.args)
      
      initialize_calldata = TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: 'initialize',
        args: args
      )
      
      TransactionHelper.get_deploy_data(
        'legacy/ERC1967Proxy', [predeploy_address, initialize_calldata]
      )
    elsif content.op == 'call'
      implementation_address = TransactionHelper.static_call(
        contract: 'legacy/ERC1967Proxy',
        address: content.data.to,
        function: '__getImplementation',
        args: []
      ).first
      
      contract_name = local_from_predeploy(implementation_address)
      args = convert_args(contract_name, data.function, data.args)
      # binding.pry
      TransactionHelper.get_function_calldata(
        contract: contract_name,
        function: data.function,
        args: args
      )
    else
      raise "Unsupported operation: #{content.op}"
    end
  end
  
  def self.convert_args(contract, function_name, args_hash)
    contract = EVMHelpers.compile_contract(contract)
    function = contract.functions.find { |f| f.name == function_name }
    inputs = function.inputs
    
    args = inputs.map do |input|
      arg_name = input.name
      arg_value = args_hash[arg_name]
      
      if input.type.starts_with?('uint') || input.type.starts_with?('int')
        arg_value = Integer(arg_value, 10) if arg_value.is_a?(String)
      end
      
      arg_value
    end
  end
  
  def self.local_from_predeploy(address)
    name = {
      "0x897d289b77c8393783829489b9ab3255c0158064": "EtherBridgeV1"
    }.with_indifferent_access.fetch(address.downcase)
    
    "legacy/#{name}"
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
