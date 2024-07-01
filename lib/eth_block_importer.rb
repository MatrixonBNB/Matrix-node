module EthBlockImporter
  extend self
  
  class BlockNotReadyToImportError < StandardError; end
  class TraceTimeoutError < StandardError; end
  
  def logger
    Rails.logger
  end
  
  def ethereum_client
    @_ethereum_client ||= begin
      client_class = ENV.fetch('ETHEREUM_CLIENT_CLASS', 'AlchemyClient').constantize
      
      client_class.new(
        api_key: ENV['ETHEREUM_CLIENT_API_KEY'],
        base_url: ENV.fetch('ETHEREUM_CLIENT_BASE_URL')
      )
    end
  end
  
  def genesis_block
    ENV.fetch('TESTNET_START_BLOCK', 6164072).to_i
  end
  
  def blocks_behind
    (cached_global_block_number - next_block_to_import) + 1
  end
  
  def cached_global_block_number
    Rails.cache.read('global_block_number') || uncached_global_block_number
  end
  
  def uncached_global_block_number
    ethereum_client.get_block_number.tap do |block_number|
      Rails.cache.write('global_block_number', block_number, expires_in: 1.second)
    end
  end
  
  def import_batch_size
    [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
  end
  
  def import_blocks_until_done
    loop do
      begin
        block_numbers = next_blocks_to_import(import_batch_size)
        
        if block_numbers.blank?
          raise BlockNotReadyToImportError.new("Block not ready")
        end
        
        import_blocks(block_numbers)
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end
  
  def ensure_genesis_blocks
    return if FacetBlock.exists?
    
    facet_genesis_block = GethDriver.client.call("eth_getBlockByNumber", ["0x0", false])
    facet_latest_block = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])
    
    unless facet_genesis_block['hash'] == facet_latest_block['hash']
      raise "Facet genesis block is not the same as the latest block on geth"
    end
    
    genesis_eth_block = ethereum_client.call("eth_getBlockByNumber", ["0x" + genesis_block.to_s(16), false])
    block_result = genesis_eth_block['result']
    
    EthBlock.create!(
      number: block_result['number'].to_i(16),
      block_hash: block_result['hash'],
      logs_bloom: block_result['logsBloom'],
      total_difficulty: block_result['totalDifficulty'].to_i(16),
      receipts_root: block_result['receiptsRoot'],
      extra_data: block_result['extraData'],
      withdrawals_root: block_result['withdrawalsRoot'],
      base_fee_per_gas: block_result['baseFeePerGas'].to_i(16),
      nonce: block_result['nonce'],
      miner: block_result['miner'],
      excess_blob_gas: block_result['excessBlobGas'].to_i(16),
      difficulty: block_result['difficulty'].to_i(16),
      gas_limit: block_result['gasLimit'].to_i(16),
      gas_used: block_result['gasUsed'].to_i(16),
      parent_beacon_block_root: block_result['parentBeaconBlockRoot'],
      size: block_result['size'].to_i(16),
      transactions_root: block_result['transactionsRoot'],
      state_root: block_result['stateRoot'],
      mix_hash: block_result['mixHash'],
      parent_hash: block_result['parentHash'],
      blob_gas_used: block_result['blobGasUsed'].to_i(16),
      timestamp: block_result['timestamp'].to_i(16)
    )
    
    FacetBlock.create!(
      number: facet_genesis_block['number'],
      block_hash: facet_genesis_block['hash'],
      eth_block_hash: block_result['hash'],
      parent_beacon_block_root: facet_genesis_block['parentBeaconBlockRoot'],
      timestamp: facet_genesis_block['timestamp'].to_i(16),
      prev_randao: Eth::Util.keccak256(block_result['hash'].hex_to_bytes + 'prevRandao').bytes_to_hex,
      base_fee_per_gas: block_result['baseFeePerGas'].to_i(16),
      gas_limit: block_result['gasLimit'].to_i(16),
      gas_used: block_result['gasUsed'].to_i(16),
      state_root: block_result['stateRoot'],
      transactions_root: block_result['transactionsRoot'],
      receipts_root: block_result['receiptsRoot'],
      parent_hash: block_result['parentHash'],
      extra_data: block_result['extraData'],
      logs_bloom: block_result['logsBloom'],
      size: block_result['size'].to_i(16),
    )
  end
  
  def import_blocks(block_numbers)
    logger.info "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current
    
    block_by_number_promises = block_numbers.map do |block_number|
      Concurrent::Promise.execute do
        [block_number, ethereum_client.get_block(block_number, true)]
      end
    end
    
    trace_promises = block_numbers.map do |block_number|
      Concurrent::Promise.execute do
        [
          block_number,
          ethereum_client.debug_trace_block_by_number(block_number)
        ]
      end
    end
    
    block_by_number_responses = block_by_number_promises.map(&:value!).sort_by(&:first)
    trace_responses = trace_promises.map(&:value!).sort_by(&:first)
    
    res = []
    
    block_by_number_responses.zip(trace_responses).each do |(block_number1, block_by_number_response), (block_number2, trace_response)|
      raise "Mismatched block numbers: #{block_number1} and #{block_number2}" unless block_number1 == block_number2
      res << import_block(block_number1, block_by_number_response, trace_response)
    end
    
    blocks_per_second = (block_numbers.length / (Time.current - start)).round(2)
    puts "Imported #{res.map(&:transactions_imported).sum} transactions"
    puts "Imported #{block_numbers.length} blocks. #{blocks_per_second} blocks / s"
    
    block_numbers
  end
  
  def import_block(block_number, block_by_number_response, trace_response)
    ActiveRecord::Base.transaction do
      validate_ready_to_import!(block_by_number_response, trace_response)
      
      trace_result = trace_response['result']
      block_result = block_by_number_response['result']
      transactions_result = block_result['transactions']
      
      parent_block = EthBlock.find_by(number: block_number - 1)
      
      if parent_block.blank?
        raise "Parent block not found"
      end
      
      if parent_block.block_hash != block_result['parentHash']
        EthBlock.where("number >= ?", parent_block.number).delete_all
        
        Airbrake.notify("
          Reorg detected: #{block_number},
          #{parent_block.block_hash},
          #{block_result['parentHash']},
          Deleting block(s): #{EthBlock.where("number >= ?", parent_block.number).pluck(:number).join(', ')}
        ")
        
        return OpenStruct.new(transactions_imported: 0)
      end
      
      eth_block = EthBlock.new(
        number: block_result['number'].to_i(16),
        block_hash: block_result['hash'],
        logs_bloom: block_result['logsBloom'],
        total_difficulty: block_result['totalDifficulty'].to_i(16),
        receipts_root: block_result['receiptsRoot'],
        extra_data: block_result['extraData'],
        withdrawals_root: block_result['withdrawalsRoot'],
        base_fee_per_gas: block_result['baseFeePerGas'].to_i(16),
        nonce: block_result['nonce'],
        miner: block_result['miner'],
        excess_blob_gas: block_result['excessBlobGas'].to_i(16),
        difficulty: block_result['difficulty'].to_i(16),
        gas_limit: block_result['gasLimit'].to_i(16),
        gas_used: block_result['gasUsed'].to_i(16),
        parent_beacon_block_root: block_result['parentBeaconBlockRoot'],
        size: block_result['size'].to_i(16),
        transactions_root: block_result['transactionsRoot'],
        state_root: block_result['stateRoot'],
        mix_hash: block_result['mixHash'],
        parent_hash: block_result['parentHash'],
        blob_gas_used: block_result['blobGasUsed'].to_i(16),
        timestamp: block_result['timestamp'].to_i(16)
      )

      eth_block.save!

      eth_transactions = []

      transactions_result.each do |tx|
        eth_transactions << EthTransaction.new(
          block_hash: block_result['hash'],
          block_number: block_result['number'].to_i(16),
          tx_hash: tx['hash'],
          y_parity: tx['yParity']&.to_i(16),
          access_list: tx['accessList'],
          transaction_index: tx['transactionIndex'].to_i(16),
          tx_type: tx['type'].to_i(16),
          nonce: tx['nonce'].to_i(16),
          input: tx['input'],
          r: tx['r'],
          s: tx['s'],
          chain_id: tx['chainId']&.to_i(16),
          v: tx['v'].to_i(16),
          gas: tx['gas'].to_i(16),
          max_priority_fee_per_gas: tx['maxPriorityFeePerGas']&.to_i(16),
          from_address: tx['from'],
          to_address: tx['to'],
          max_fee_per_gas: tx['maxFeePerGas']&.to_i(16),
          value: tx['value'].to_i(16),
          gas_price: tx['gasPrice'].to_i(16)
        )
      end

      EthTransaction.import!(eth_transactions)

      order_counter = Struct.new(:count).new(0)

      traces = trace_result.flat_map do |trace|
        process_trace(trace, eth_block, order_counter)
      end
      
      EthCall.import!(traces.flatten.sort_by(&:call_index))
      
      FacetBlockImporter.from_eth_block(eth_block)

      OpenStruct.new(transactions_imported: eth_transactions.size)
    end
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("eth_blocks") && e.message.include?("number")
      logger.info "Block Importer: Block #{block_number} already exists"
      raise ActiveRecord::Rollback
    else
      raise
    end
  end
  
  def process_trace(trace, eth_block, order_counter, parent_traced_call = nil)
    result = trace['result']
    current_order = order_counter.count
    order_counter.count += 1

    traces = []
    
    traced_call = EthCall.new(
      block_hash: eth_block.block_hash,
      block_number: eth_block.number,
      transaction_hash: trace['txHash'],
      from_address: result['from'],
      to_address: result['to'],
      gas: result['gas'].to_i(16),
      gas_used: result['gasUsed'].to_i(16),
      input: result['input'],
      output: result['output'],
      value: result['value'],
      call_type: result['type'],
      error: result['error'],
      revert_reason: result['revertReason'],
      call_index: current_order,
      parent_call_index: parent_traced_call&.call_index
    )
    
    traces << traced_call
     
    if result['calls']
      traces += result['calls'].map do |sub_call|
        process_trace(
          { 'txHash' => trace['txHash'], 'result' => sub_call },
          eth_block,
          order_counter,
          traced_call
        )
      end
    end
    
    traces
  end
  
  def validate_ready_to_import!(block_by_number_response, trace_response)
    if trace_response.dig('error', 'code') == -32000
      raise TraceTimeoutError, "Trace timed out on block #{block_by_number_response.dig('result', 'number').inspect}"
    end
    
    is_ready = block_by_number_response.present? &&
      block_by_number_response.dig('result', 'hash').present? &&
      trace_response.present? &&
      trace_response.dig('error', 'code') != -32600 &&
      trace_response.dig('error', 'message') != "Block being processed - please try again later"
    
    unless is_ready
      raise BlockNotReadyToImportError.new("Block not ready")
    end
  end
  
  def import_next_block
    block_number = next_block_to_import
    
    import_blocks([block_number])
  end
  
  def next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def next_blocks_to_import(n)
    ensure_genesis_blocks
    
    max_db_block = EthBlock.maximum(:number)
    
    unless max_db_block
      raise "No blocks in the database"
    end
    
    start_block = max_db_block + 1
    
    (start_block...(start_block + n)).to_a
  end
end
