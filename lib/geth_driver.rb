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
    
    PredeployManager.write_genesis_json(clear_cache: false)
    # SolidityCompiler.compile_all_legacy_files
    
    teardown_rspec_geth
    
    @temp_datadir = Dir.mktmpdir('geth_datadir_', '/tmp')
    log_file_location = Rails.root.join('tmp', 'geth.log').to_s
    if File.exist?(log_file_location)
      File.delete(log_file_location)
    end
    
    genesis_filename = ChainIdManager.on_mainnet? ? "facet-mainnet.json" : "facet-sepolia.json"
    
    system("cd #{geth_dir} && make geth && ./build/bin/geth init --cache.preimages --state.scheme=hash --datadir #{@temp_datadir} facet-chain/#{genesis_filename}")
    
    geth_command = [
      "#{geth_dir}/build/bin/geth",
      "--datadir", @temp_datadir,
      "--http",
      "--http.api", "eth,net,web3,debug",
      "--http.vhosts", "*",
      "--authrpc.jwtsecret", "/tmp/jwtsecret",
      "--http.port", http_port,
      "--authrpc.port", authrpc_port,
      "--discovery.port", discovery_port,
      "--port", discovery_port,
      "--authrpc.addr", "localhost",
      "--authrpc.vhosts", "*",
      "--nodiscover",
      "--maxpeers", "0",
      "--log.file", log_file_location,
      "--syncmode", "full",
      "--gcmode", "archive",
      "--history.state", "0",
      "--history.transactions", "0",
      "--nocompaction",
      "--rollup.disabletxpoolgossip",
      "--cache", "12000",
      "--cache.preimages",
    ]
    
    FileUtils.rm(log_file_location) if File.exist?(log_file_location)
    
    pid = Process.spawn(*geth_command)
    Process.detach(pid)
    
    File.write('tmp/geth_pid', pid)
    
    begin
      Timeout.timeout(30) do
        loop do
          break if File.exist?(log_file_location) && File.read(log_file_location).include?("NAT mapped port")
          sleep 0.5
        end
      end
    rescue Timeout::Error
      raise "Geth setup did not complete within the expected time"
    end
  end
  
  def self.teardown_rspec_geth
    if File.exist?('tmp/geth_pid')
      pid = File.read('tmp/geth_pid').to_i
      begin
        # Kill the specific geth process
        Process.kill('TERM', pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD => e
        puts e.message
      ensure
        File.delete('tmp/geth_pid')
      end
    end
    
    # Clean up the temporary data directory
    Dir.glob('/tmp/geth_datadir_*').each do |dir|
      FileUtils.rm_rf(dir)
    end
  end
  
  def init_command
    http_port = ENV.fetch('NON_AUTH_GETH_RPC_URL').split(':').last
    authrpc_port = ENV.fetch('GETH_RPC_URL').split(':').last
    discovery_port = ENV.fetch('GETH_DISCOVERY_PORT')
    
    genesis_filename = ChainIdManager.on_mainnet? ? "facet-mainnet.json" : "facet-sepolia.json"
    
    command = [
      "make geth &&",
      "rm -rf ./datadir &&",
      "./build/bin/geth init --cache.preimages --state.scheme=hash --datadir ./datadir facet-chain/#{genesis_filename} &&",
      "./build/bin/geth --datadir ./datadir",
      "--http",
      "--http.api 'eth,net,web3,debug'",
      "--http.vhosts=\"*\"",
      "--authrpc.jwtsecret /tmp/jwtsecret",
      "--http.port #{http_port}",
      "--authrpc.port #{authrpc_port}",
      "--discovery.port #{discovery_port}",
      "--port #{discovery_port}",
      "--authrpc.addr localhost",
      "--authrpc.vhosts=\"*\"",
      "--nodiscover",
      "--cache 16000",
      "--cache.preimages",
      "--maxpeers 0",
      # "--verbosity 2",
      "--syncmode full",
      "--gcmode archive",
      "--history.state 0",
      "--history.transactions 0",
      "--nocompaction",
      "--rollup.disabletxpoolgossip",
      "console"
    ].join(' ')

    puts command
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
  
  def propose_block(transactions, new_facet_block, head_block, safe_block, finalized_block, reorg: false)
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
    
    if payload['transactions'].empty?
      raise "no transactions in returned payload"
    end

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
    
    unless new_payload_response['latestValidHash'] == payload['blockHash']
      raise "New payload was not valid: #{status}"
    end
  
    new_safe_block = safe_block
    new_finalized_block = finalized_block
    
    fork_choice_state = {
      headBlockHash: payload['blockHash'],
      safeBlockHash: new_safe_block.block_hash, # should this also be payload blockhash?
      finalizedBlockHash: new_finalized_block.block_hash
    }
    
    fork_choice_response = client.call("engine_forkchoiceUpdatedV#{version}", [fork_choice_state, nil])

    status = fork_choice_response['payloadStatus']['status']
    unless status == 'VALID'
      raise "Fork choice update was not valid: #{status}"
    end
    
    unless fork_choice_response['payloadStatus']['latestValidHash'] == payload['blockHash']
      binding.irb
      raise "New payload was not valid: #{status}"
    end
    
    payload
  end
end
