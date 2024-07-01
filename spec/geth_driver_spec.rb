require "rails_helper"

RSpec.describe GethDriver do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }

  # \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json
  
  # ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  
  # \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  # make geth && \rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --networkid 1027303 --http --http.api "eth,net,web3,debug,engine" --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --nodiscover --maxpeers 0 console
  
  
  describe 'block and deposit transaction' do
    it 'deploys a contract with a deposit tx' do
      initial_count = 5
      data = get_deploy_data('contracts/Counter', [initial_count])
      
      hsh = '0x7d6609a3e3d61aece11a50a15c16e3d8ca0c973f804938fb9ff581298e4297fa'
      
      deposit_tx = Eth::Tx::Deposit.new({
        source_hash: hsh,
        from: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
        mint: 0,
        value: 0,
        gas_limit: 1e6.to_i,
        is_system_tx: false,
        data: data,
      })
      
      transactions = [deposit_tx.encoded.bytes_to_hex]
      
      start_block = client.call("eth_getBlockByNumber", ["latest", true])
      engine_api.propose_block(transactions, EthBlock.new(parent_beacon_block_root: "0x" + "0" * 64))
      
      latest_block = client.call("eth_getBlockByNumber", ["latest", true])
      expect(latest_block).not_to be_nil
      expect(latest_block['transactions'].size).to eq(transactions.size)

      deposit_tx_response = latest_block['transactions'].first
      expect(deposit_tx_response['input']).to eq(deposit_tx.payload.bytes_to_hex)
      
      ap deposit_tx_receipt = client.call("eth_getTransactionReceipt", [deposit_tx_response['hash']])
      
      expect(deposit_tx_receipt).not_to be_nil
      expect(deposit_tx_receipt['from']).to eq(deposit_tx.from)
      
      expect(deposit_tx_receipt['to']).to eq(deposit_tx.to)
      
      sender_balance_before = client.call("eth_getBalance", [deposit_tx.from, start_block['number']])
      sender_balance_after = client.call("eth_getBalance", [deposit_tx.from, "latest"])

      # Retrieve gas used and gas price
      gas_used = deposit_tx_receipt['gasUsed'].to_i(16)
      gas_price = deposit_tx_receipt['effectiveGasPrice'].to_i(16) # ? deposit_tx_receipt['effectiveGasPrice'].to_i(16) : deposit_tx_receipt['gasPrice'].to_i(16)
      total_gas_cost = gas_used * gas_price

      # Validate balance change considering mint amount and gas cost
      balance_change = sender_balance_after.to_i(16) - sender_balance_before.to_i(16)
      expected_balance_change = deposit_tx.mint - total_gas_cost
      # binding.pry
      expect(balance_change).to eq(expected_balance_change)

      contract_address = deposit_tx_receipt['contractAddress']
      
      logs = deposit_tx_receipt['logs']
      expect(logs).not_to be_empty

      deployed_event_topic = "0x" + Eth::Util.keccak256("Deployed(address,string)").unpack1('H*')
      log_event = logs.find { |log| log['topics'].include?(deployed_event_topic) }
      
      expect(log_event).not_to be_nil
      expect(log_event['address']).to eq(contract_address)
      expect(log_event['topics'][1]).to eq("0x" + deposit_tx.from[2..].rjust(64, '0'))
      
      decoded_data = Eth::Abi.decode(["string"], log_event['data'].hex_to_bytes)
      expect(decoded_data[0]).to eq("Hello, World!")
   
      contract = get_contract('contracts/Counter', contract_address)
      function = contract.parent.function_hash['getCount']
      
      data = function.get_call_data
      
      result = client.call("eth_call", [{
        to: contract_address,
        data: data
      }, "latest"])
      
      expect(function.parse_result(result).first).to eq(initial_count)
      
      function = contract.parent.function_hash['increment']
      
      data = function.get_call_data
      
      # Create a new transaction to call increment()
      increment_tx = Eth::Tx::Deposit.new({
        source_hash: SecureRandom.hex(32),
        from: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
        to: contract_address,
        mint: 0,
        value: 0,
        gas_limit: 1e6.to_i,
        is_system_tx: false,
        data: data,
      })

      transactions = [increment_tx.encoded.bytes_to_hex]

      # Propose a new block with the increment transaction
      engine_api.propose_block(transactions, EthBlock.new(parent_beacon_block_root: "0x" + "0" * 64))

      # Verify the new block and the increment transaction
      latest_block = client.call("eth_getBlockByNumber", ["latest", true])
      expect(latest_block).not_to be_nil
      expect(latest_block['transactions'].size).to eq(transactions.size)

      increment_tx_response = latest_block['transactions'].first
      expect(increment_tx_response['input']).to eq(increment_tx.payload.bytes_to_hex)

      increment_tx_receipt = client.call("eth_getTransactionReceipt", [increment_tx_response['hash']])
      expect(increment_tx_receipt).not_to be_nil
      expect(increment_tx_receipt['from']).to eq(increment_tx.from)
      expect(increment_tx_receipt['to']).to eq(increment_tx.to)

      function = contract.parent.function_hash['getCount']
      
      data = function.get_call_data
      
      result = client.call("eth_call", [{
        to: contract_address,
        data: data
      }, "latest"])
      
      expect(function.parse_result(result).first).to eq(initial_count + 1)
    end
    
    it 'creates a block with the correct properties and verifies the deposit transaction' do
      deposit_tx = Eth::Tx::Deposit.new({
        source_hash: "0x" + SecureRandom.hex(32),
        from: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
        to: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        mint: 100,
        value: 0,
        gas_limit: 21000,
        is_system_tx: false,
        data: "0x",
      })
      
      transactions = [deposit_tx.encoded.bytes_to_hex]
      
      start_block = client.call("eth_getBlockByNumber", ["latest", true])
      
      # Step 3: Propose a block
      engine_api.propose_block(transactions, EthBlock.new(parent_beacon_block_root: "0x" + "0" * 64))

      # Step 4: Verify the block was created with the correct properties
      latest_block = client.call("eth_getBlockByNumber", ["latest", true])
      expect(latest_block).not_to be_nil
      expect(latest_block['transactions'].size).to eq(transactions.size)

      # Step 5: Verify the deposit transaction
      deposit_tx_response = latest_block['transactions'].first
      
      expect(deposit_tx_response['input']).to eq(deposit_tx.payload.bytes_to_hex)
      
      deposit_tx_receipt = client.call("eth_getTransactionReceipt", [deposit_tx_response['hash']])
      expect(deposit_tx_receipt).not_to be_nil
      expect(deposit_tx_receipt['from']).to eq(deposit_tx.from)
      expect(deposit_tx_receipt['to']).to eq(deposit_tx.to)
      
      sender_balance_before = client.call("eth_getBalance", [deposit_tx.from, start_block['number']])
      sender_balance_after = client.call("eth_getBalance", [deposit_tx.from, "latest"])

      # Retrieve gas used and gas price
      gas_used = deposit_tx_receipt['gasUsed'].to_i(16)
      gas_price = deposit_tx_receipt['effectiveGasPrice'].to_i(16) # ? deposit_tx_receipt['effectiveGasPrice'].to_i(16) : deposit_tx_receipt['gasPrice'].to_i(16)
      total_gas_cost = gas_used * gas_price

      # Validate balance change considering mint amount and gas cost
      balance_change = sender_balance_after.to_i(16) - sender_balance_before.to_i(16)
      expected_balance_change = deposit_tx.mint - total_gas_cost
      # binding.pry
      expect(balance_change).to eq(expected_balance_change)
    end
  end
end
