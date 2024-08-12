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
    ENV.fetch('START_BLOCK').to_i - 1
  end
  
  def v2_fork_block
    ENV['V2_FORK_BLOCK'].presence&.to_i
  end
  
  def in_v2?(block_number)
    v2_fork_block.blank? || block_number >= v2_fork_block
  end
  
  def in_v1?(block_number)
    !in_v2?(block_number)
  end
  
  def blocks_behind
    (cached_global_block_number - next_block_to_import) + 1
  end
  
  def cached_global_block_number
    Rails.cache.read('global_block_number') || uncached_global_block_number
  end
  
  def uncached_global_block_number
    ethereum_client.get_block_number.tap do |block_number|
      Rails.cache.write('global_block_number', block_number, expires_in: 12.seconds)
    end
  end
  
  def import_batch_size
    [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
  end
  
  def import_blocks_until_done
    MemeryExtensions.clear_all_caches!
    # SolidityCompiler.compile_all_legacy_files
    
    ensure_genesis_blocks
    
    alchemy_responses = {}

    loop do
      begin
        block_numbers = next_blocks_to_import(import_batch_size)
        
        if block_numbers.blank?
          raise BlockNotReadyToImportError.new("Block not ready")
        end
        
        next_start_block = block_numbers.last + 1
        next_block_numbers = (next_start_block...(next_start_block + import_batch_size)).to_a
        
        blocks_to_import = block_numbers + next_block_numbers
        
        blocks_to_import -= alchemy_responses.keys
        
        alchemy_responses.reverse_merge!(get_blocks_promises(blocks_to_import))
        
        BlockImportBatchContext.set(
          imported_facet_transactions: [],
          imported_facet_transaction_receipts: []
        ) do
          import_blocks(block_numbers, alchemy_responses)
        end
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end
  
  def ensure_genesis_blocks
    ActiveRecord::Base.transaction do
      facet_block_exists = FacetBlock.exists?
      eth_block_exists = EthBlock.exists?
      
      if facet_block_exists && eth_block_exists
        return
      end
      
      unless !facet_block_exists && !eth_block_exists
        raise "Inconsistent state"
      end
      
      facet_genesis_block = GethDriver.client.call("eth_getBlockByNumber", ["0x0", false])
      facet_latest_block = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])
      
      unless facet_genesis_block['hash'] == facet_latest_block['hash']
        raise "Facet genesis block is not the same as the latest block on geth"
      end
      
      genesis_eth_block = ethereum_client.call("eth_getBlockByNumber", ["0x" + genesis_block.to_s(16), false])
      
      eth_block = EthBlock.from_rpc_result(genesis_eth_block)
      eth_block.save!
      
      current_max_block_number = FacetBlock.maximum(:number).to_i

      facet_block = FacetBlock.from_eth_block(eth_block, current_max_block_number + 1)
      facet_block.from_rpc_response(facet_genesis_block)
      facet_block.save!
    end
  end
  
  def get_blocks_promises(block_numbers)
    block_numbers.map do |block_number|
      block_promise = Concurrent::Promise.execute do
         ethereum_client.get_block(block_number, true)
      end
      
      if block_numbers.any? { |block_number| in_v2?(block_number) }
        trace_promise = Concurrent::Promise.execute do
          ethereum_client.debug_trace_block_by_number(block_number)
        end
      end
      
      if block_numbers.any? { |block_number| in_v1?(block_number) }
        receipt_promise = Concurrent::Promise.execute do
          ethereum_client.get_transaction_receipts(
            block_number,
            blocks_behind: 1_000
          )
        end
      end
      
      empty_promise = Concurrent::Promise.execute { {} }
      
      [block_number, {
        block: block_promise,
        trace: trace_promise || empty_promise,
        receipts: receipt_promise || empty_promise
      }.with_indifferent_access]
    end.to_h
  end
  
  def import_blocks(block_numbers, alchemy_responses)
    logger.info "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current

    block_responses = Benchmark.msr("block_responses") { alchemy_responses.select do |block_number, _|
      block_numbers.include?(block_number)
    end.to_h.transform_values! do |hsh|
      hsh.transform_values!(&:value!)
    end }
  
    alchemy_responses.reject! { |block_number, _| block_responses.key?(block_number) }
    
    eth_blocks = []
    eth_transactions = []
    eth_calls = []
    facet_blocks = []
    all_facet_txs = []
    all_receipts = []
    res = []
    proposed_blocks = []
    
    # Initialize in-memory representation of blocks
    current_max_facet_block_number = FacetBlock.maximum(:number).to_i
    
    # Get the earliest block
    earliest = FacetBlock.order(number: :asc).first
    
    # Initialize in-memory representation of blocks
    in_memory_blocks = FacetBlock.where(number: (current_max_facet_block_number - 64 - block_numbers.size)..current_max_facet_block_number).index_by(&:number)
    
    ActiveRecord::Base.transaction do
      locked_blocks = FacetBlock.where("number >= ?", current_max_facet_block_number).
        order(:number).
        limit(import_batch_size + 1).
        lock("FOR UPDATE SKIP LOCKED").to_a

      if locked_blocks.size != 1
        logger.info "More than one block is locked or no block is locked. Another process is ahead or no blocks to process. Aborting import."
        return
      end
      
      block_numbers.each.with_index do |block_number, index|
        block_response = block_responses[block_number]
        
        block_result = block_response['block']['result']
        trace_result = block_response['trace']['result']
        receipt_result = block_response['receipts']['result']
        
        facet_block_number = current_max_facet_block_number + index + 1
        
        if index == 0
          reorg_happened = handle_potential_reorg(
            block_number,
            block_result['parentHash']
          )
          
          if reorg_happened
            res << OpenStruct.new(
              facet_block: [],
              transactions_imported: []
            )
            
            return
          end
        end

        # Determine the head, safe, and finalized blocks
        head_block = in_memory_blocks[facet_block_number - 1] || earliest
        safe_block = in_memory_blocks[facet_block_number - 32] || earliest
        finalized_block = in_memory_blocks[facet_block_number - 64] || earliest
  
        eth_block = EthBlock.from_rpc_result(block_response['block'])
        eth_blocks << eth_block
  
        new_eth_transactions = EthTransaction.from_rpc_result(block_result, receipt_result)
        eth_transactions.concat(new_eth_transactions)
        
        if trace_result
          new_eth_calls = EthCall.from_trace_result(trace_result, eth_block)
          eth_calls.concat(new_eth_calls)
        end
  
        facet_block, facet_txs = propose_facet_block(
          eth_block,
          eth_calls: new_eth_calls,
          eth_transactions: new_eth_transactions,
          facet_block_number: facet_block_number,
          earliest: earliest,
          head_block: head_block,
          safe_block: safe_block,
          finalized_block: finalized_block
        )

        proposed_blocks << {
          facet_block: facet_block,
          facet_txs: facet_txs
        }
        
        in_memory_blocks[facet_block_number] = facet_block
        
        # block_ethscriptions.each(&:clear_caches_if_upgrade!)
        
        res << OpenStruct.new(
          facet_block: facet_block,
          transactions_imported: facet_txs
        )
      end
      
      results = Parallel.map(proposed_blocks, in_threads: 10) do |proposed_block|
        fill_in_block_data(proposed_block[:facet_block], proposed_block[:facet_txs])
      end
      
      # Mutate shared data structures in the main thread
      results.each do |facet_block, facet_txs, facet_receipts|
        facet_blocks << facet_block
        all_facet_txs.concat(facet_txs)
        all_receipts.concat(facet_receipts)
        
        BlockImportBatchContext.imported_facet_transaction_receipts.concat(facet_receipts)
        BlockImportBatchContext.imported_facet_transactions.concat(facet_txs)
      end
      
      eth_tx_hashes_to_save = all_facet_txs.map(&:eth_transaction_hash).to_set
      
      eth_transactions_to_save = eth_transactions.select do |tx|
        eth_tx_hashes_to_save.include?(tx.tx_hash)
      end
      
      eth_calls_to_save = eth_calls.select do |call|
        eth_tx_hashes_to_save.include?(call.transaction_hash)
      end
    
      EthBlock.import!(eth_blocks)
      EthTransaction.import!(eth_transactions_to_save)
      EthCall.import!(eth_calls_to_save)
      
      FacetBlock.import!(facet_blocks)
      FacetTransaction.import!(all_facet_txs)
      FacetTransactionReceipt.import!(all_receipts)
    end
  
    elapsed_time = Time.current - start
  
    blocks = res.map(&:facet_block)
    total_gas = blocks.sum(&:gas_used)
    total_transactions = res.map(&:transactions_imported).flatten.count
    blocks_per_second = (blocks.length / elapsed_time).round(2)
    transactions_per_second = (total_transactions / elapsed_time).round(2)
    total_gas_millions = (total_gas / 1_000_000.0).round(2)
    average_gas_per_block_millions = (total_gas / blocks.length / 1_000_000.0).round(2)
    gas_per_second_millions = (total_gas / elapsed_time / 1_000_000.0).round(2)
  
    puts "Time elapsed: #{elapsed_time.round(2)} s"
    puts "Imported #{block_numbers.length} blocks. #{blocks_per_second} blocks / s"
    puts "Imported #{total_transactions} transactions (#{transactions_per_second} / s)"
    puts "Total gas used: #{total_gas_millions} million (avg: #{average_gas_per_block_millions} million / block)"
    puts "Gas per second: #{gas_per_second_millions} million / s"
  
    block_numbers
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
    ensure_genesis_blocks
    block_number = next_block_to_import
    
    import_blocks([block_number])
  end
  
  def handle_potential_reorg(next_block_number, parent_hash)
    parent_block = EthBlock.find_by_number(next_block_number - 1)
      
    unless parent_block
      raise "No last imported eth block found"
    end
    
    if parent_block.block_hash != parent_hash
      blocks_to_delete = EthBlock.where("number >= ?", parent_block.number - 1).to_a
      deleted_message = "Deleting block(s): #{blocks_to_delete.map(&:number).join(', ')}"
      
      blocks_to_delete.each(&:destroy)

      Airbrake.notify("
        Reorg detected: #{parent_block.number},
        #{parent_block.block_hash},
        #{parent_hash},
        #{deleted_message}
      ")
      
      return true
    end
    
    return false
  end
  
  def next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def next_blocks_to_import(n)
    max_db_block = EthBlock.maximum(:number)
    
    unless max_db_block
      raise "No blocks in the database"
    end
    
    start_block = max_db_block + 1
    
    (start_block...(start_block + n)).to_a
  end
  
  def facet_txs_from_ethscriptions_in_block(eth_block, ethscriptions, facet_block)
    results = Parallel.map(ethscriptions.sort_by(&:transaction_index).each_with_index, in_threads: 10) do |(ethscription, idx)|
      ethscription.clear_caches_if_upgrade!
      
      facet_tx = FacetTransaction.from_eth_tx_and_ethscription(
        ethscription,
        idx,
        eth_block,
        ethscriptions.count,
        facet_block
      )
      
      [idx, facet_tx]
    end
  
    results.sort_by { |idx, _| idx }.map { |_, facet_tx| facet_tx }
  rescue => e
    binding.irb
    raise
  end
  
  def fill_in_block_data(facet_block, facet_txs)
    geth_block = geth_driver.client.call("eth_getBlockByNumber", ["0x" + facet_block.number.to_s(16), true])
    
    if facet_txs.present?
      receipts_data = geth_driver.client.call("eth_getBlockReceipts", ["0x" + facet_block.number.to_s(16)])
    end
    
    facet_block.from_rpc_response(geth_block)
    
    if facet_txs.blank?
      return [facet_block, facet_txs, []]
    end
    
    receipts_data_by_hash = receipts_data.index_by { |receipt| receipt['transactionHash'] }
    
    facet_txs_by_source_hash = facet_txs.index_by(&:source_hash)
    
    receipts = []
    
    geth_block['transactions'].each do |tx|
      receipt_details = receipts_data_by_hash[tx['hash']]
      
      facet_tx = facet_txs_by_source_hash[tx['sourceHash']]
      raise unless facet_tx

      facet_tx.assign_attributes(
        tx_hash: tx['hash'],
        transaction_index: receipt_details['transactionIndex'].to_i(16),
        deposit_receipt_version: tx['depositReceiptVersion'].to_i(16),
        gas: tx['gas'].to_i(16),
        tx_type: tx['type']
      )
      
      facet_receipt = FacetTransactionReceipt.new(
        transaction_hash: tx['hash'],
        block_hash: facet_block.block_hash,
        block_number: facet_block.number,
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
      
      receipts << facet_receipt
    end
    
    [facet_block, facet_txs, receipts]
  end
  
  def propose_facet_block(eth_block, eth_calls: nil, eth_transactions:, facet_block_number:, earliest:, head_block:, safe_block:, finalized_block:)
    facet_block = FacetBlock.from_eth_block(eth_block, facet_block_number)
    
    facet_txs = if in_v2?(eth_block.number)
      FacetTransaction.from_eth_transactions_in_block(
        eth_block,
        eth_transactions,
        eth_calls,
        facet_block
      )
    else
      ethscriptions = Ethscription.from_eth_transactions(eth_transactions)
          
      facet_txs_from_ethscriptions_in_block(
        eth_block,
        ethscriptions,
        facet_block
      )
    end

    attributes_tx = FacetTransaction.l1_attributes_tx_from_blocks(eth_block, facet_block)
    facet_txs = facet_txs.sort_by(&:eth_call_index).unshift(attributes_tx)

    payload = facet_txs.map(&:to_facet_payload)
    
    response = geth_driver.propose_block(
      payload,
      facet_block,
      earliest,
      head_block,
      safe_block,
      finalized_block
    )
    
    facet_block.assign_attributes(
      block_hash: response['blockHash'],
      number: response['blockNumber'].to_i(16),
    )
    
    facet_txs.each do |facet_tx|
      facet_tx.assign_attributes(
        block_hash: facet_block.block_hash,
        block_number: facet_block.number,
      )
    end
    
    return [facet_block, facet_txs]
  rescue => e
    binding.irb
    raise
  end
  
  def geth_driver
    @_geth_driver ||= GethDriver
  end
end
