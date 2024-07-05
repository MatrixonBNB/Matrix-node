module GethDriver
  extend self
  attr_reader :password
  
  def client
    @_client ||= GethClient.new(ENV.fetch('GETH_RPC_URL'))
  end
  
  def propose_block(transactions, new_facet_block, reorg: false)
    # TODO: make sure that the geth node's latest block is the same as the ruby's
    earliest = FacetBlock.order(number: :asc).first
    
    head_block = FacetBlock.find_by(number: new_facet_block.number - 1) || earliest
    safe_block = FacetBlock.find_by(number: head_block.number - 32) || earliest
    finalized_block = FacetBlock.find_by(number: head_block.number - 64) || earliest
    
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
  
  def self.t
    tx = Eth::Tx.new({
      nonce: 0,
      chain_id: 0xFace7,
      max_gas_fee: 69 * Eth::Unit::GWEI,
      gas_limit: 230_420,
      priority_fee: 0,
      to: "0xCaA29806044A08E533963b2e573C1230A2cd9a2d",
      value: 0,
      data: "testing",
      access_list: [],
    })
    
    return tx.unsigned_encoded
    
    
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
