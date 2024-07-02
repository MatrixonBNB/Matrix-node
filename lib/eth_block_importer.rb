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
    ActiveRecord::Base.transaction do
      return if FacetBlock.exists?
    
      facet_genesis_block = GethDriver.client.call("eth_getBlockByNumber", ["0x0", false])
      facet_latest_block = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])
      
      unless facet_genesis_block['hash'] == facet_latest_block['hash']
        raise "Facet genesis block is not the same as the latest block on geth"
      end
      
      genesis_eth_block = ethereum_client.call("eth_getBlockByNumber", ["0x" + genesis_block.to_s(16), false])
      
      eth_block = EthBlock.from_rpc_result(genesis_eth_block)
      eth_block.save!
      
      facet_block = FacetBlock.from_eth_block(eth_block)
      facet_block.from_rpc_response(facet_genesis_block)
      facet_block.save!
    end
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
      res << import_block(block_by_number_response, trace_response)
    end
    
    blocks_per_second = (block_numbers.length / (Time.current - start)).round(2)
    puts "Imported #{res.map(&:transactions_imported).sum} transactions"
    puts "Imported #{block_numbers.length} blocks. #{blocks_per_second} blocks / s"
    
    block_numbers
  end
  
  def import_block(block_by_number_response, trace_response)
    ActiveRecord::Base.transaction do
      validate_ready_to_import!(block_by_number_response, trace_response)
      
      trace_result = trace_response['result']
      block_result = block_by_number_response['result']
      transactions_result = block_result['transactions']
      block_number = block_result['number'].to_i(16)
      
      parent_block = EthBlock.find_by!(number: block_number - 1)
      
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
      
      eth_block = EthBlock.from_rpc_result(block_by_number_response)

      eth_block.save!

      eth_transactions = EthTransaction.from_rpc_result(block_by_number_response)

      EthTransaction.import!(eth_transactions)
      
      traces = EthCall.from_trace_result(trace_result, eth_block)
      
      EthCall.import!(traces)
      
      propose_facet_block(eth_block)

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

  def propose_facet_block(eth_block)
    eth_block.reload
    
    facet_block = FacetBlock.from_eth_block(eth_block)
    
    facet_txs = eth_block.eth_transactions.includes(:eth_calls).map do |tx|
      tx.eth_calls.map do |call|
        next if call.error.present?

        facet_tx = FacetTransaction.from_eth_call_and_tx(call, tx)
        
        next unless facet_tx
        next unless facet_tx.chain_id == facet_chain_id
        
        facet_tx
      end
    end.flatten.compact
    
    facet_txs.group_by(&:eth_transaction).each do |eth_tx, grouped_facet_txs|
      in_tx_count = grouped_facet_txs.count
      
      outer_call = eth_tx.eth_calls.sort_by(&:call_index).first
      
      gas_used = outer_call.gas_used
      base_fee = eth_block.base_fee_per_gas
      total_mint_amount = gas_used * base_fee
      mint_amount_per_tx = total_mint_amount / in_tx_count
      
      grouped_facet_txs.each do |facet_tx|
        facet_tx.mint = mint_amount_per_tx
      end
    end
    
    payload = facet_txs.sort_by(&:eth_call_index).map(&:to_payload)
    
    response = geth_driver.propose_block(
      payload,
      facet_block
    )

    geth_block = geth_driver.client.call("eth_getBlockByNumber", [response['blockNumber'], true])
    
    facet_block.from_rpc_response(geth_block)

    facet_block.save!
    
    geth_block['transactions'].each do |tx|
      receipt_details = geth_driver.client.call("eth_getTransactionReceipt", [tx['hash']])

      facet_tx = facet_txs.detect { |facet_tx| facet_tx.source_hash == tx['sourceHash'] }
      raise unless facet_tx

      facet_tx.update!(
        tx_hash: tx['hash'],
        block_hash: response['blockHash'],
        block_number: response['blockNumber'].to_i(16),
        transaction_index: receipt_details['transactionIndex'].to_i(16),
        deposit_receipt_version: tx['depositReceiptVersion'].to_i(16),
        gas: tx['gas'].to_i(16),
        tx_type: tx['type']
        # gas_limit: tx['gasLimit'].to_i(16),
        # gas_used: receipt_details['gasUsed'].to_i(16),
      )

      FacetTransactionReceipt.create!(
        transaction_hash: tx['hash'],
        block_hash: response['blockHash'],
        block_number: response['blockNumber'].to_i(16),
        contract_address: receipt_details['contractAddress'],
        cumulative_gas_used: receipt_details['cumulativeGasUsed'].to_i(16),
        deposit_nonce: tx['nonce'].to_i(16),
        deposit_receipt_version: tx['type'].to_i(16),
        effective_gas_price: receipt_details['effectiveGasPrice'].to_i(16),
        from_address: tx['from'],
        gas_used: receipt_details['gasUsed'].to_i(16),
        logs: receipt_details['logs'],
        logs_bloom: receipt_details['logsBloom'],
        status: receipt_details['status'].to_i(16),
        to_address: tx['to'],
        transaction_index: receipt_details['transactionIndex'].to_i(16),
        tx_type: tx['type']
      )
    end
  end
  
  def geth_driver
    @_geth_driver ||= GethDriver
  end
  
  def facet_chain_id
    0xface7
  end
end
