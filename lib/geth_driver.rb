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
    ENV.fetch('GETH_RPC_URL').sub("8551", "8545")
  end
  
  def trace_transaction(tx_hash)
    non_auth_client.call("debug_traceTransaction", [tx_hash, {
      enableMemory: true,
      disableStack: false,
      disableStorage: false,
      enableReturnData: true,
      debug: true,
      tracer: "callTracer"
    }])
  end
  
  def propose_block(transactions, new_facet_block, reorg: false)
    # TODO: make sure that the geth node's latest block is the same as the ruby's
    earliest = FacetBlock.order(number: :asc).first
    
    target_numbers = [
      new_facet_block.number - 1,
      new_facet_block.number - 32,
      new_facet_block.number - 64
    ]
    
    blocks = FacetBlock.where(number: target_numbers).index_by(&:number)
    
    head_block = blocks[new_facet_block.number - 1] || earliest
    safe_block = blocks[new_facet_block.number - 32] || earliest
    finalized_block = blocks[new_facet_block.number - 64] || earliest
    
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
    
    # Recall that a batch contains a list of transactions to be included in a specific L2 block.

    # A batch is encoded as batch_version ++ content, where content depends on the batch_version. Prior to the Delta upgrade, batches all have batch_version 0 and are encoded as described below.
    
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

    new_safe_block = FacetBlock.find_by(number: head_block.number - 32) || earliest
    new_finalized_block = FacetBlock.find_by(number: head_block.number - 63) || earliest
    
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
