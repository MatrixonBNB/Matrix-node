module GethDriver
  extend self
  attr_reader :password
  
  def self.setup_rspec_geth
    geth_dir = ENV.fetch('LOCAL_GETH_DIR')

    EthBlock.delete_all
    
    Ethscription.write_alloc_to_genesis
    
    system("cd #{geth_dir} && make geth && \\rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json")
    
    pid = Process.spawn(%{cd #{geth_dir} && ./build/bin/geth --datadir ./datadir --http --http.api 'eth,net,web3,debug,engine' --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --authrpc.port 8551 --authrpc.addr localhost --authrpc.vhosts="*" --nodiscover --maxpeers 0 > geth.log 2>&1})
    Process.detach(pid)
    
    sleep 1
  end
  
  def init_command
    http_port = ENV.fetch('NON_AUTH_GETH_RPC_URL').split(':').last
    authrpc_port = ENV.fetch('GETH_RPC_URL').split(':').last
    discovery_port = ENV.fetch('GETH_DISCOVERY_PORT')
    
    puts %{
      make geth && \\rm -rf ./datadir && ./build/bin/geth init --datadir ./datadir facet-chain/genesis3.json && ./build/bin/geth --datadir ./datadir --http --http.api 'eth,net,web3,debug,engine' --http.vhosts=* --authrpc.jwtsecret /tmp/jwtsecret --http.port #{http_port} --authrpc.port #{authrpc_port} --discovery.port #{discovery_port} --port #{discovery_port} --authrpc.addr localhost --authrpc.vhosts="*" --nodiscover --cache 64000 --cache.preimages=true --maxpeers 0 --verbosity 2 --syncmode full --gcmode archive --history.state 0 --history.transactions 0 --nocompaction --rollup.disabletxpoolgossip=true console
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
      parentBeaconBlockRoot: new_facet_block.parent_beacon_block_root,
      prevRandao: new_facet_block.prev_randao,
      suggestedFeeRecipient: "0x0000000000000000000000000000000000000000",
      withdrawals: [],
      noTxPool: true,
      transactions: transactions,
      gasLimit: "0x" + 300e6.to_i.to_s(16),
    }
    
    fork_choice_response = client.call("engine_forkchoiceUpdatedV3", [fork_choice_state, payload_attributes])
    raise "Fork choice update failed: #{fork_choice_response['error']}" if fork_choice_response['error']
    
    payload_id = fork_choice_response['payloadId']
    raise "Fork choice update did not return a payload ID" unless payload_id

    # Step 2: Get the payload
    get_payload_response = client.call("engine_getPayloadV3", [payload_id])
    raise "Get payload failed: #{get_payload_response['error']}" if get_payload_response['error']

    payload = get_payload_response['executionPayload']
    
    payload['transactions'] = transactions

    new_payload_response = client.call("engine_newPayloadV3", [
      payload,
      [],
      new_facet_block.parent_beacon_block_root
    ])
    
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
