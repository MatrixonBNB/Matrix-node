require "rails_helper"

RSpec.describe "Uniswap" do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  
  # \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json
  
  # ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  
  # \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  # make geth && \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  describe 'block and deposit transaction' do
    it "deploys uniswap" do
      mint_amount = 1e18.to_i
      
      facet_data = get_deploy_data('contracts/MyToken', [])
            
      from_address = "0x000000000000000000000000000000000000000a"
      
      res = create_and_import_block(
        facet_data: facet_data,
        to_address: nil,
        from_address: from_address
      )
      
      weth_address = res.receipts_imported.first.contract_address
      
      call_contract_function(
        contract: 'contracts/MyToken',
        address: weth_address,
        from: from_address,
        function: 'mint',
        args: [from_address, mint_amount]
      )
      
      res = create_and_import_block(
        facet_data: facet_data,
        to_address: nil,
        from_address: from_address
      )
      
      token_address = res.receipts_imported.first.contract_address
      
      res = call_contract_function(
        contract: 'contracts/MyToken',
        address: token_address,
        from: from_address,
        function: 'mint',
        args: [from_address, mint_amount]
      )
      
      facet_data = get_deploy_data('uniswap-v2/contracts/UniswapV2Factory', [from_address])
      
      res = create_and_import_block(
        facet_data: facet_data,
        to_address: nil,
        from_address: from_address,
        gas_limit: 10e6.to_i
      )
      
      factory_address = res.receipts_imported.first.contract_address
      
      factory = get_contract('uniswap-v2/contracts/UniswapV2Factory', factory_address)
      
      facet_data = get_deploy_data('uniswap-v2/contracts/UniswapV2Router02', [factory_address, weth_address])
      
      res = create_and_import_block(
        facet_data: facet_data,
        to_address: nil,
        from_address: from_address,
        gas_limit: 5_000_000
      )
      
      router_address = res.receipts_imported.first.contract_address
      
      res = call_contract_function(
        contract: 'uniswap-v2/contracts/UniswapV2Factory',
        address: factory_address,
        from: from_address,
        function: 'createPair',
        args: [token_address, weth_address],
        gas_limit: 3_000_000
      )

      sig = "0x" + factory.parent.events.detect{|i| i.name == "PairCreated"}.signature
      
      log = res.receipts_imported.first.logs.detect { |log| log['topics'][0] == sig }
      
      decoded_log = Eth::Abi::Event::LogDescription.new(factory.parent.abi.detect{|i| i['name'] == 'PairCreated'}, log)
      
      pool_address = decoded_log.kwargs[:pair]
      
      res = call_contract_function(
        contract: 'contracts/MyToken',
        address: weth_address,
        from: from_address,
        function: 'approve',
        args: [router_address, mint_amount]
      )

      res = call_contract_function(
        contract: 'contracts/MyToken',
        address: token_address,
        from: from_address,
        function: 'approve',
        args: [router_address, mint_amount]
      )
      
      result = static_call(
        contract: 'contracts/MyToken',
        address: token_address,
        function: 'allowance',
        args: [from_address, router_address]
      )
      
      expect(result).to eq(mint_amount)
      
      result = static_call(
        contract: 'contracts/MyToken',
        address: weth_address,
        function: 'allowance',
        args: [from_address, router_address]
      )
      
      expect(result).to eq(mint_amount)
      
      result = static_call(
        contract: 'contracts/MyToken',
        address: token_address,
        function: 'balanceOf',
        args: [from_address]
      )
      
      expect(result).to eq(mint_amount)
      
      result = static_call(
        contract: 'contracts/MyToken',
        address: weth_address,
        function: 'balanceOf',
        args: [from_address]
      )
      
      expect(result).to eq(mint_amount)
      
      res = call_contract_function(
        contract: 'uniswap-v2/contracts/UniswapV2Router02',
        address: router_address,
        from: from_address,
        function: 'addLiquidity',
        args: [token_address, weth_address, 10_000, 10_000, 1, 1, from_address, (Time.now.to_i + 36000)]
      )
      
      res = call_contract_function(
        contract: 'uniswap-v2/contracts/UniswapV2Router02',
        address: router_address,
        from: from_address,
        function: 'swapExactTokensForTokens',
        args: [5000, 1, [token_address, weth_address], from_address, (Time.now.to_i + 36000)]
      )
    end
  end
end
