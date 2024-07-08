require "rails_helper"

RSpec.describe "Uniswap" do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  let(:from_address) { '0xC2172a6315c1D7f6855768F843c420EbB36eDa96'.downcase }
  let(:first_tx_receipt) {
    OpenStruct.new(JSON.parse("{\"id\":1,\"transaction_hash\":\"0x8351e2aa33080394eace1cc0700e935bdfb03747eb00d68524beb1920f4df102\",\"from_address\":\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\",\"status\":\"success\",\"function\":\"constructor\",\"args\":{\"name\":\"Facet Ether\",\"symbol\":\"FETH\",\"trustedSmartContract\":\"0xbE73b799BE0b492c36b19bf7a69D4a6b41D90214\"},\"logs\":[],\"block_timestamp\":1706742600,\"error\":null,\"to_contract_address\":null,\"effective_contract_address\":\"0x1673540243e793b0e77c038d4a88448eff524dce\",\"created_contract_address\":\"0x1673540243e793b0e77c038d4a88448eff524dce\",\"block_number\":5193575,\"transaction_index\":19,\"block_blockhash\":\"0xca539d77ba96b421ead69ab8eb4954059da8f0dc997ce9cf6744e7101ff9b702\",\"return_value\":null,\"call_type\":\"create\",\"gas_price\":1596301384,\"gas_used\":112408,\"transaction_fee\":179437045972672,\"created_at\":\"2024-06-10T18:46:13.377Z\",\"updated_at\":\"2024-06-10T18:46:13.377Z\",\"gas_stats\":{\"s\":{\"count\":5,\"gas_used\":0.0025},\"address\":{\"count\":1,\"gas_used\":0.01},\"require\":{\"count\":1,\"gas_used\":0.0005},\"msg_sender\":{\"count\":1,\"gas_used\":0.01},\"StorageBaseSet\":{\"count\":5,\"gas_used\":0.1},\"TypedVariableNe\":{\"count\":1,\"gas_used\":0.01},\"ContractFunction\":{\"count\":3,\"gas_used\":1.5},\"ExternalContractCall\":{\"count\":1,\"gas_used\":0.5},\"ContractFunctionArgGet\":{\"count\":18,\"gas_used\":0.009000000000000005}},\"facet_gas_used\":2.1420000000000003,\"runtime_ms\":68.236}"))
  }
  let(:first_ethscription) {
    Ethscription.new(JSON.parse("{\"id\":7,\"transaction_hash\":\"0x8351e2aa33080394eace1cc0700e935bdfb03747eb00d68524beb1920f4df102\",\"block_number\":5193575,\"block_blockhash\":\"0xca539d77ba96b421ead69ab8eb4954059da8f0dc997ce9cf6744e7101ff9b702\",\"transaction_index\":19,\"creator\":\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\",\"initial_owner\":\"0x00000000000000000000000000000000000face7\",\"block_timestamp\":1706742600,\"content_uri\":\"data:application/vnd.facet.tx+json;rule=esip6,{\\\"op\\\":\\\"create\\\",\\\"data\\\":{\\\"init_code_hash\\\":\\\"0xbae85b82353ff68e9cee3036897d289b77c8393783829489b9ab3255c0158064\\\",\\\"args\\\":{\\\"trustedSmartContract\\\":\\\"0xbE73b799BE0b492c36b19bf7a69D4a6b41D90214\\\",\\\"name\\\":\\\"Facet Ether\\\",\\\"symbol\\\":\\\"FETH\\\"},\\\"source_code\\\":\\\"pragma(:rubidity, \\\\\\\"1.0.0\\\\\\\")\\\\ncontract(:ERC20, abstract: true) {\\\\n  event(:Transfer, { from: :address, to: :address, amount: :uint256 })\\\\n  event(:Approval, { owner: :address, spender: :address, amount: :uint256 })\\\\n  string(:public, :name)\\\\n  string(:public, :symbol)\\\\n  uint8(:public, :decimals)\\\\n  uint256(:public, :totalSupply)\\\\n  mapping(({ address: :uint256 }), :public, :balanceOf)\\\\n  mapping(({ address: mapping(address: :uint256) }), :public, :allowance)\\\\n  constructor(name: :string, symbol: :string, decimals: :uint8) {\\\\n    s.name=name\\\\n    s.symbol=symbol\\\\n    s.decimals=decimals\\\\n  }\\\\n  function(:approve, { spender: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\\\\n    s.allowance[msg.sender][spender] = amount\\\\n    emit(:Approval, owner: msg.sender, spender: spender, amount: amount)\\\\n    return true\\\\n  }\\\\n  function(:transfer, { to: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\\\\n    require(s.balanceOf[msg.sender] \\u003e= amount, \\\\\\\"Insufficient balance\\\\\\\")\\\\n    s.balanceOf[msg.sender] -= amount\\\\n    s.balanceOf[to] += amount\\\\n    emit(:Transfer, from: msg.sender, to: to, amount: amount)\\\\n    return true\\\\n  }\\\\n  function(:transferFrom, { from: :address, to: :address, amount: :uint256 }, :public, :virtual, returns: :bool) {\\\\n    allowed = s.allowance[from][msg.sender]\\\\n    require(s.balanceOf[from] \\u003e= amount, \\\\\\\"Insufficient balance\\\\\\\")\\\\n    require(allowed \\u003e= amount, \\\\\\\"Insufficient allowance\\\\\\\")\\\\n    s.allowance[from][msg.sender] = allowed - amount\\\\n    s.balanceOf[from] -= amount\\\\n    s.balanceOf[to] += amount\\\\n    emit(:Transfer, from: from, to: to, amount: amount)\\\\n    return true\\\\n  }\\\\n  function(:_mint, { to: :address, amount: :uint256 }, :internal, :virtual) {\\\\n    s.totalSupply += amount\\\\n    s.balanceOf[to] += amount\\\\n    emit(:Transfer, from: address(0), to: to, amount: amount)\\\\n  }\\\\n  function(:_burn, { from: :address, amount: :uint256 }, :internal, :virtual) {\\\\n    require(s.balanceOf[from] \\u003e= amount, \\\\\\\"Insufficient balance\\\\\\\")\\\\n    s.balanceOf[from] -= amount\\\\n    s.totalSupply -= amount\\\\n    emit(:Transfer, from: from, to: address(0), amount: amount)\\\\n  }\\\\n}\\\\ncontract(:Upgradeable, abstract: true) {\\\\n  address(:public, :upgradeAdmin)\\\\n  event(:ContractUpgraded, { oldHash: :bytes32, newHash: :bytes32 })\\\\n  event(:UpgradeAdminChanged, { newUpgradeAdmin: :address })\\\\n  constructor(upgradeAdmin: :address) {\\\\n    s.upgradeAdmin=upgradeAdmin\\\\n  }\\\\n  function(:setUpgradeAdmin, { newUpgradeAdmin: :address }, :public) {\\\\n    require(msg.sender == s.upgradeAdmin, \\\\\\\"NOT_AUTHORIZED\\\\\\\")\\\\n    s.upgradeAdmin=newUpgradeAdmin\\\\n    emit(:UpgradeAdminChanged, newUpgradeAdmin: newUpgradeAdmin)\\\\n  }\\\\n  function(:upgradeAndCall, { newHash: :bytes32, newSource: :string, migrationCalldata: :string }, :public) {\\\\n    upgrade(newHash: newHash, newSource: newSource)\\\\n    (success, data) = address(this).call(migrationCalldata)\\\\n    require(success, \\\\\\\"Migration failed\\\\\\\")\\\\n  }\\\\n  function(:upgrade, { newHash: :bytes32, newSource: :string }, :public) {\\\\n    currentHash = this.currentInitCodeHash\\\\n    require(msg.sender == s.upgradeAdmin, \\\\\\\"NOT_AUTHORIZED\\\\\\\")\\\\n    this.upgradeImplementation(newHash, newSource)\\\\n    emit(:ContractUpgraded, oldHash: currentHash, newHash: newHash)\\\\n  }\\\\n}\\\\ncontract(:EtherBridge, is: [:ERC20, :Upgradeable], upgradeable: true) {\\\\n  event(:BridgedIn, { to: :address, amount: :uint256 })\\\\n  event(:InitiateWithdrawal, { from: :address, amount: :uint256, withdrawalId: :bytes32 })\\\\n  event(:WithdrawalComplete, { to: :address, amount: :uint256, withdrawalId: :bytes32 })\\\\n  address(:public, :trustedSmartContract)\\\\n  mapping(({ bytes32: :uint256 }), :public, :withdrawalIdAmount)\\\\n  mapping(({ address: :bytes32 }), :public, :userWithdrawalId)\\\\n  constructor(name: :string, symbol: :string, trustedSmartContract: :address) {\\\\n    require(trustedSmartContract != address(0), \\\\\\\"Invalid smart contract\\\\\\\")\\\\n    self.ERC20.constructor(name: name, symbol: symbol, decimals: 18)\\\\n    self.Upgradeable.constructor(upgradeAdmin: msg.sender)\\\\n    s.trustedSmartContract=trustedSmartContract\\\\n  }\\\\n  function(:bridgeIn, { to: :address, amount: :uint256 }, :public) {\\\\n    require(msg.sender == s.trustedSmartContract, \\\\\\\"Only the trusted smart contract can bridge in tokens\\\\\\\")\\\\n    _mint(to: to, amount: amount)\\\\n    emit(:BridgedIn, to: to, amount: amount)\\\\n  }\\\\n  function(:bridgeOut, { amount: :uint256 }, :public) {\\\\n    withdrawalId = tx.current_transaction_hash\\\\n    require(s.userWithdrawalId[msg.sender] == bytes32(0), \\\\\\\"Withdrawal pending\\\\\\\")\\\\n    require(s.withdrawalIdAmount[withdrawalId] == 0, \\\\\\\"Already bridged out\\\\\\\")\\\\n    require(amount \\u003e 0, \\\\\\\"Invalid amount\\\\\\\")\\\\n    s.userWithdrawalId[msg.sender] = withdrawalId\\\\n    s.withdrawalIdAmount[withdrawalId] = amount\\\\n    _burn(from: msg.sender, amount: amount)\\\\n    emit(:InitiateWithdrawal, from: msg.sender, amount: amount, withdrawalId: withdrawalId)\\\\n  }\\\\n  function(:markWithdrawalComplete, { to: :address, withdrawalId: :bytes32 }, :public) {\\\\n    require(msg.sender == s.trustedSmartContract, \\\\\\\"Only the trusted smart contract can mark withdrawals as complete\\\\\\\")\\\\n    require(s.userWithdrawalId[to] == withdrawalId, \\\\\\\"Withdrawal id not found\\\\\\\")\\\\n    amount = s.withdrawalIdAmount[withdrawalId]\\\\n    s.withdrawalIdAmount[withdrawalId] = 0\\\\n    s.userWithdrawalId[to] = bytes32(0)\\\\n    emit(:WithdrawalComplete, to: to, amount: amount, withdrawalId: withdrawalId)\\\\n  }\\\\n}\\\\n\\\"}}\",\"mimetype\":\"application/vnd.facet.tx+json\",\"processed_at\":\"2024-06-10T18:46:13.467Z\",\"processing_state\":\"success\",\"processing_error\":null,\"gas_price\":1596301384,\"gas_used\":112408,\"transaction_fee\":179437045972672,\"created_at\":\"2024-06-10T18:28:41.195Z\",\"updated_at\":\"2024-06-10T18:28:41.195Z\"}"))
  }
  
  let(:second_tx_receipt) {
    JSON.parse("{\"id\":2,\"transaction_hash\":\"0xfbde0d201e92b07852141be00fecc4eb34b1a26f6611d07dbf812a819b9beda1\",\"from_address\":\"0xbe73b799be0b492c36b19bf7a69d4a6b41d90214\",\"status\":\"success\",\"function\":\"bridgeIn\",\"args\":{\"to\":\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\",\"amount\":\"100000000000000000\"},\"logs\":[{\"data\":{\"to\":\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\",\"from\":\"0x0000000000000000000000000000000000000000\",\"amount\":100000000000000000},\"event\":\"Transfer\",\"log_index\":0,\"contractType\":\"EtherBridge\",\"contractAddress\":\"0x1673540243e793b0e77c038d4a88448eff524dce\"},{\"data\":{\"to\":\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\",\"amount\":100000000000000000},\"event\":\"BridgedIn\",\"log_index\":1,\"contractType\":\"EtherBridge\",\"contractAddress\":\"0x1673540243e793b0e77c038d4a88448eff524dce\"}],\"block_timestamp\":1706742780,\"error\":null,\"to_contract_address\":\"0x1673540243e793b0e77c038d4a88448eff524dce\",\"effective_contract_address\":\"0x1673540243e793b0e77c038d4a88448eff524dce\",\"created_contract_address\":null,\"block_number\":5193589,\"transaction_index\":28,\"block_blockhash\":\"0x8b231d39255bc052dddb0565b505a1e9340d0a82781442e5d214ee8bc24a4b60\",\"return_value\":null,\"call_type\":\"call\",\"gas_price\":1605668904,\"gas_used\":42541,\"transaction_fee\":68306760845064,\"created_at\":\"2024-06-10T18:46:13.519Z\",\"updated_at\":\"2024-06-10T18:46:13.519Z\",\"gas_stats\":{\"s\":{\"count\":5,\"gas_used\":0.0025},\"emit\":{\"count\":2,\"gas_used\":0.02},\"address\":{\"count\":1,\"gas_used\":0.01},\"require\":{\"count\":1,\"gas_used\":0.0005},\"msg_sender\":{\"count\":1,\"gas_used\":0.01},\"StorageBaseGet\":{\"count\":4,\"gas_used\":0.04},\"StorageBaseSet\":{\"count\":1,\"gas_used\":0.02},\"TypedVariable+\":{\"count\":2,\"gas_used\":0.02},\"TypedVariableEq\":{\"count\":1,\"gas_used\":0.01},\"ContractFunction\":{\"count\":2,\"gas_used\":1.0},\"StorageMappingGet\":{\"count\":1,\"gas_used\":0.03},\"StorageMappingSet\":{\"count\":1,\"gas_used\":0.05},\"ExternalContractCall\":{\"count\":1,\"gas_used\":0.5},\"ContractFunctionArgGet\":{\"count\":21,\"gas_used\":0.010500000000000006}},\"facet_gas_used\":1.7234999999999987,\"runtime_ms\":17.503}", object_class: OpenStruct)
  }
  
  let(:second_ethscription) {
    Ethscription.new(JSON.parse("{\"id\":8,\"transaction_hash\":\"0xfbde0d201e92b07852141be00fecc4eb34b1a26f6611d07dbf812a819b9beda1\",\"block_number\":5193589,\"block_blockhash\":\"0x8b231d39255bc052dddb0565b505a1e9340d0a82781442e5d214ee8bc24a4b60\",\"transaction_index\":28,\"creator\":\"0xbe73b799be0b492c36b19bf7a69d4a6b41d90214\",\"initial_owner\":\"0x00000000000000000000000000000000000face7\",\"block_timestamp\":1706742780,\"content_uri\":\"data:application/vnd.facet.tx+json;rule=esip6,{\\\"op\\\":\\\"call\\\",\\\"data\\\":{\\\"to\\\":\\\"0x1673540243e793b0e77c038d4a88448eff524dce\\\",\\\"function\\\":\\\"bridgeIn\\\",\\\"args\\\":{\\\"to\\\":\\\"0xc2172a6315c1d7f6855768f843c420ebb36eda97\\\",\\\"amount\\\":\\\"100000000000000000\\\"}}}\",\"mimetype\":\"application/vnd.facet.tx+json\",\"processed_at\":\"2024-06-10T18:46:13.535Z\",\"processing_state\":\"success\",\"processing_error\":null,\"gas_price\":1605668904,\"gas_used\":42541,\"transaction_fee\":68306760845064,\"created_at\":\"2024-06-10T18:28:41.195Z\",\"updated_at\":\"2024-06-10T18:28:41.195Z\"}"))
  }
  
  before(:all) do
    GethDriver.teardown_rspec_geth
    GethDriver.setup_rspec_geth
  end
  
  it 'imports old tx #1' do
    input = first_ethscription.facet_tx_input
    
    proxy_res = create_and_import_block(
      facet_data: input,
      to_address: nil,
      from_address: first_tx_receipt.from_address
    )
    
    expect(proxy_res.receipts_imported.first.contract_address).to eq(
      first_tx_receipt.created_contract_address
    )
    
    input = second_ethscription.facet_tx_input
    
    proxy_res = create_and_import_block(
      facet_data: input,
      to_address: second_tx_receipt.to_contract_address,
      from_address: second_tx_receipt.from_address
    )
    
    receipt = proxy_res.receipts_imported.first
    status = receipt.status == 1 ? "success" : "failure"
    
    expect(status).to eq(
      second_tx_receipt.status
    )
  end
  
  it 'does another one' do
    facet_data = get_deploy_data('legacy/AirdropERC20V1', [])
          
    implementation_res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: from_address
    )
    
    implementation_address = implementation_res.receipts_imported.first.contract_address
    
    initialize_calldata = get_function_calldata(
      contract: 'legacy/AirdropERC20V1',
      function: 'initialize',
      args: [
        "ethx",          # name
        "ethx",          # symbol
        from_address,    # owner
        18,              # decimals
        21000000000000000000000000,  # maxSupply
        1000000000000000000000,      # perMintLimit
      ]
    )
    
    proxy_res = create_and_import_block(
      facet_data: get_deploy_data(
        'legacy/ERC1967Proxy', [implementation_address, initialize_calldata]
      ),
      to_address: nil,
      from_address: from_address
    )
  end
  
  it "deploy basic proxy" do
    mint_amount = 1e18.to_i
    
    facet_data = get_deploy_data('legacy/EtherBridgeV1', [])
          
    from_address = "0xC2172a6315c1D7f6855768F843c420EbB36eDa96".downcase
    trusted_smart_contract = "0xbE73b799BE0b492c36b19bf7a69D4a6b41D90214".downcase
    
    implementation_res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: from_address
    )
    
    implementation_address = implementation_res.receipts_imported.first.contract_address
    
    initialize_calldata = get_function_calldata(
      contract: 'legacy/EtherBridgeV1',
      function: 'initialize',
      args: [
        "Facet Ether",
        "FETH",
        trusted_smart_contract
      ]
    )
    
    proxy_res = create_and_import_block(
      facet_data: get_deploy_data(
        'legacy/ERC1967Proxy', [implementation_address, initialize_calldata]
      ),
      to_address: nil,
      from_address: from_address
    )
    
    proxy_address = proxy_res.receipts_imported.first.contract_address
    
    bridge_in_calldata = get_function_calldata(
      contract: 'legacy/EtherBridgeV1',
      function: 'bridgeIn',
      args: [
        from_address,
        mint_amount
      ]
    )
    
    call_contract_function(
      contract: 'legacy/EtherBridgeV1',
      address: proxy_address,
      from: trusted_smart_contract,
      function: 'bridgeIn',
      args: [from_address, mint_amount]
    )
    
    result = static_call(
      contract: 'legacy/EtherBridgeV1',
      address: proxy_address,
      function: 'balanceOf',
      args: [from_address]
    )
    
    expect(result).to eq(mint_amount)
  end
end
