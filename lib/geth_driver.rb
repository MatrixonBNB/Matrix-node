module GethDriver
  extend self
  attr_reader :password
  
  def self.setup_rspec_geth
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')
    http_port = ENV.fetch('NON_AUTH_GETH_RPC_URL').split(':').last
    authrpc_port = ENV.fetch('GETH_RPC_URL').split(':').last
    discovery_port = ENV.fetch('GETH_DISCOVERY_PORT')
    
    EthBlock.all.each(&:destroy)
    FacetBlock.all.each(&:destroy)
    
    Ethscription.write_alloc_to_genesis
    
    system("cd #{geth_dir} && make geth && \\rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json")
    
    pid = Process.spawn(%{cd #{geth_dir} && ./build/bin/geth --datadir ./datadir --http --http.api 'eth,net,web3,debug' --http.vhosts="*" --authrpc.jwtsecret /tmp/jwtsecret -http.port #{http_port} --authrpc.port #{authrpc_port} --discovery.port #{discovery_port} --port #{discovery_port} --authrpc.addr localhost --authrpc.vhosts="*" --nodiscover --maxpeers 0 > g.log 2>&1})
    Process.detach(pid)
    
    sleep 1
  end
  
  def init_command
    http_port = ENV.fetch('NON_AUTH_GETH_RPC_URL').split(':').last
    authrpc_port = ENV.fetch('GETH_RPC_URL').split(':').last
    discovery_port = ENV.fetch('GETH_DISCOVERY_PORT')
    
    puts %{
      make geth && \\rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --http --http.api 'eth,net,web3,debug' --http.vhosts="*" --authrpc.jwtsecret /tmp/jwtsecret --http.port #{http_port} --authrpc.port #{authrpc_port} --discovery.port #{discovery_port} --port #{discovery_port} --authrpc.addr localhost --authrpc.vhosts="*" --nodiscover --cache 64000 --cache.preimages=true --maxpeers 0 --verbosity 2 --syncmode full --gcmode archive --history.state 0 --history.transactions 0 --nocompaction --rollup.disabletxpoolgossip=true console
    }.strip
  end
  
  def self.teardown_rspec_geth
    system("pkill -f geth")
  end
  
  def client
    @_client ||= GethClient.new(ENV.fetch('GETH_RPC_URL'))
  end
  
  def non_auth_client
    @_non_auth_client ||= GethClient.new(non_authed_rpc_url)
  end
  
  def non_authed_rpc_url
    ENV.fetch('NON_AUTH_GETH_RPC_URL')
  end
  
  def trace_transaction(tx_hash)
    # contract = EVMHelpers.compile_contract("legacy/NFTCollectionVa11")
    # function = contract.parent.function_hash['contractURI']
    # data = function.get_call_data
    
    # result = GethDriver.non_auth_client.call("eth_call", [{
    #   to: "0xdcf075616bf2d26775c3500ea3c1513e0442966a",
    #   data: data
    # }, "latest"])
    
    # function.parse_result(result)
    
    non_auth_client.call("debug_traceTransaction", [tx_hash, {
      enableMemory: true,
      disableStack: false,
      disableStorage: false,
      enableReturnData: true,
      debug: true,
      tracer: "callTracer"
    }])
  end
  
  def propose_block(transactions, new_facet_block, earliest, head_block, safe_block, finalized_block, reorg: false)
    head_block_hash = head_block.block_hash
    safe_block_hash = safe_block.block_hash
    finalized_block_hash = finalized_block.block_hash
    
    fork_choice_state = {
      headBlockHash: head_block_hash,
      safeBlockHash: safe_block_hash,
      finalizedBlockHash: finalized_block_hash,
    }
    
    payload_attributes = {
      timestamp: "0x" + new_facet_block.timestamp.to_s(16),
      prevRandao: new_facet_block.prev_randao,
      suggestedFeeRecipient: "0x0000000000000000000000000000000000000000",
      withdrawals: [],
      noTxPool: true,
      transactions: transactions,
      gasLimit: "0x" + FacetBlock::GAS_LIMIT.to_s(16),
    }
    
    if new_facet_block.parent_beacon_block_root
      version = 3
      payload_attributes[:parentBeaconBlockRoot] = new_facet_block.parent_beacon_block_root
    else
      version = 2
    end
    
    fork_choice_response = client.call("engine_forkchoiceUpdatedV#{version}", [fork_choice_state, payload_attributes])
    raise "Fork choice update failed: #{fork_choice_response['error']}" if fork_choice_response['error']
    
    payload_id = fork_choice_response['payloadId']
    unless payload_id
      binding.irb
      raise "Fork choice update did not return a payload ID"
    end

    get_payload_response = client.call("engine_getPayloadV#{version}", [payload_id])
    raise "Get payload failed: #{get_payload_response['error']}" if get_payload_response['error']

    payload = get_payload_response['executionPayload']
    
    # Should this already be there?
    payload['transactions'] = transactions

    new_payload_request = [
      payload
    ]
    
    if version == 3
      new_payload_request << []
      new_payload_request << new_facet_block.parent_beacon_block_root
    end
    
    new_payload_response = client.call("engine_newPayloadV#{version}", new_payload_request)
    
    status = new_payload_response['status']
    unless status == 'VALID'
      raise "New payload was not valid: #{status}"
    end
  
    new_safe_block = safe_block
    new_finalized_block = finalized_block
    
    fork_choice_state = {
      headBlockHash: payload['blockHash'],
      safeBlockHash: new_safe_block.block_hash,
      finalizedBlockHash: new_finalized_block.block_hash
    }
    
    fork_choice_response = client.call("engine_forkchoiceUpdatedV3", [fork_choice_state, nil])

    status = fork_choice_response['payloadStatus']['status']
    unless status == 'VALID'
      raise "Fork choice update was not valid: #{status}"
    end

    payload
  end
end

# func sanityCheckPayload(payload *eth.ExecutionPayload) error {
# 	// Sanity check payload before inserting it
# 	if len(payload.Transactions) == 0 {
# 		return errors.New("no transactions in returned payload")
# 	}
# 	if payload.Transactions[0][0] != types.DepositTxType {
# 		return fmt.Errorf("first transaction was not deposit tx. Got %v", payload.Transactions[0][0])
# 	}
# 	// Ensure that the deposits are first
# 	lastDeposit, err := lastDeposit(payload.Transactions)
# 	if err != nil {
# 		return fmt.Errorf("failed to find last deposit: %w", err)
# 	}
# 	// Ensure no deposits after last deposit
# 	for i := lastDeposit + 1; i < len(payload.Transactions); i++ {
# 		tx := payload.Transactions[i]
# 		deposit, err := isDepositTx(tx)
# 		if err != nil {
# 			return fmt.Errorf("failed to decode transaction idx %d: %w", i, err)
# 		}
# 		if deposit {
# 			return fmt.Errorf("deposit tx (%d) after other tx in l2 block with prev deposit at idx %d", i, lastDeposit)
# 		}
# 	}
# 	return nil
# }