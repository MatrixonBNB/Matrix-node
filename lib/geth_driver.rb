class GethDriver
  attr_reader :client, :password
  
  def initialize(node_url = 'http://localhost:8551')
    @client = GethClient.new(node_url)
  end
  
  def reorg_chain(to_block)
    target_block = client.call("eth_getBlockByNumber", ["0x" + to_block.to_s(16), false])
    
    fork_choice_state = {
      headBlockHash: target_block['hash'],
      safeBlockHash: target_block['hash'],
      finalizedBlockHash: target_block['hash'],
    }
    
    client.call("engine_forkchoiceUpdatedV3", [fork_choice_state, nil])
  end
  
  def propose_block(transactions, l1_origin_block, timestamp = Time.now.to_i)
    latest_block = client.call("eth_getBlockByNumber", ["latest", false])
    
    payload_attributes = {
      timestamp: "0x" + (latest_block['timestamp'].to_i(16) + 12).to_s(16),
      
      # In Ecotone it MUST be set to the parentBeaconBlockRoot from the L1 Origin block of the L2 block.
      parentBeaconBlockRoot: '0x0000000000000000000000000000000000000000000000000000000000000000',
      # Need to set genesis block to a real L1 block for this to work
      # parentBeaconBlockRoot: l1_origin_block.parent_beacon_block_root,
      
      prevRandao: "0x" + SecureRandom.hex(32),
      random: "0x" + SecureRandom.hex(32),
      suggestedFeeRecipient: "0x0000000000000000000000000000000000000000",
      withdrawals: [],
      noTxPool: true,
      transactions: transactions,
      gasLimit: "0x" + 30e6.to_i.to_s(16),
    }
    
    # Recall that a batch contains a list of transactions to be included in a specific L2 block.

    # A batch is encoded as batch_version ++ content, where content depends on the batch_version. Prior to the Delta upgrade, batches all have batch_version 0 and are encoded as described below.
    
    fork_choice_state = {
      headBlockHash: latest_block['hash'],
      safeBlockHash: latest_block['hash'],
      finalizedBlockHash: latest_block['hash'],
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

    new_payload_response = client.call("engine_newPayloadV3", [payload, [], '0x0000000000000000000000000000000000000000000000000000000000000000'])
    
    status = new_payload_response['status']
    unless status == 'VALID'
      raise "New payload was not valid: #{status}"
    end

    fork_choice_state = {
      headBlockHash: payload['blockHash'],
      safeBlockHash: payload['blockHash'],
      finalizedBlockHash: payload['blockHash']
    }
    fork_choice_response = client.call("engine_forkchoiceUpdatedV3", [fork_choice_state, nil])

    status = fork_choice_response['payloadStatus']['status']
    unless status == 'VALID'
      raise "Fork choice update was not valid: #{status}"
    end

    payload
  end
  
  def self.t
    engine_api = new
    
    tx = Eth::Tx.new({
      chain_id: 0xFace7,
      nonce: 6,
      priority_fee: 3 * Eth::Unit::GWEI,
      max_gas_fee: 69 * Eth::Unit::GWEI,
      gas_limit: 230_420,
      to: "0xCaA29806044A08E533963b2e573C1230A2cd9a2d",
      value: 0.069423 * Eth::Unit::ETHER,
      data: "Foo Bar Ruby Ethereum",
      access_list: [],
    })
    
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
    
    private_key = Array.new(31) { 0 } + [1]
    key = Eth::Key.new(priv: private_key.uint8_array_to_bytes)
    
    tx.sign(key)
    
    # transactions = [tx.encoded.bytes_to_hex]
    transactions = []
    transactions << deposit_tx.encoded.bytes_to_hex
    
    engine_api.propose_block(transactions)
  end
end
