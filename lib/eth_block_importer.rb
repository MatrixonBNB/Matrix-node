class EthBlockImporter
  include Singleton
  include Memery
  
  class BlockNotReadyToImportError < StandardError; end
  class TraceTimeoutError < StandardError; end
  
  attr_accessor :l1_rpc_results, :facet_block_cache, :ethereum_client, :eth_block_cache
  
  def initialize
    @l1_rpc_results = {}
    @facet_block_cache = {}
    @eth_block_cache = {}
    
    @ethereum_client ||= EthRpcClient.new(
      base_url: ENV.fetch('ETHEREUM_CLIENT_BASE_URL')
    )
    
    set_eth_block_starting_points
    populate_facet_block_cache
  end
  
  def current_max_facet_block_number
    facet_block_cache.keys.max
  end
  
  def current_max_eth_block_number
    eth_block_cache.keys.max
  end
  
  def current_max_eth_block
    eth_block_cache[current_max_eth_block_number]
  end
  
  def populate_facet_block_cache
    last_64_block_numbers = ([0, current_max_facet_block_number - 64].max..current_max_facet_block_number).to_a
    
    results = Parallel.map(last_64_block_numbers, in_threads: 10) do |block_number|
      hex_block_number = "0x" + block_number.to_s(16)
      FacetBlock.from_rpc_result(geth_driver.client.call("eth_getBlockByNumber", [hex_block_number, true]))
    end
    
    facet_block_cache.merge!(results.index_by { |result| result.number })
  end
  
  def logger
    Rails.logger
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
    (current_block_number - next_block_to_import) + 1
  end
  
  def current_block_number
    ethereum_client.get_block_number
  end
  memoize :current_block_number, ttl: 12.seconds
  
  def import_batch_size
    [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
  end
  
  def set_eth_block_starting_points
    latest_block = GethDriver.client.call("eth_getBlockByNumber", ["latest", true])
    
    if latest_block['number'].to_i(16) == 0
      facet_block_cache[0] = FacetBlock.from_rpc_result(latest_block)
      eth_block_cache[genesis_block] = EthBlock.from_rpc_result(ethereum_client.get_block(genesis_block)['result'])
      
      return
    end
    
    attributes_tx = latest_block['transactions'].first
        
    attributes = L1AttributesTxCalldata.decode(attributes_tx['input'])
    
    start_number_candidate = attributes[:number]
    
    l2_start_number_candidate = latest_block['number'].to_i(16)
    
    loop do
      l1_result = ethereum_client.get_block(start_number_candidate)['result']
      l1_hash = l1_result['hash']
      
      # Fetch the corresponding L2 block and decode its attributes
      l2_block = GethDriver.client.call("eth_getBlockByNumber", ["0x#{l2_start_number_candidate.to_s(16)}", true])
      l2_attributes_tx = l2_block['transactions'].first
      l2_attributes = L1AttributesTxCalldata.decode(l2_attributes_tx['input'])
      our_hash = l2_attributes[:hash]
      our_number = l2_attributes[:number]

      if l1_hash == our_hash && our_number == start_number_candidate
        eth_block_cache[start_number_candidate] = EthBlock.from_rpc_result(l1_result)
        facet_block_cache[l2_start_number_candidate] = FacetBlock.from_rpc_result(l2_block)
        return
      else
        l2_start_number_candidate -= 1
        start_number_candidate -= 1
      end
      
      binding.irb
      raise "No starting block found"
    end
  end
  
  def import_blocks_until_done
    MemeryExtensions.clear_all_caches!
    
    loop do
      begin
        block_numbers = next_blocks_to_import(import_batch_size)
        
        if block_numbers.blank?
          raise BlockNotReadyToImportError.new("Block not ready")
        end
        
        populate_l1_rpc_results(block_numbers)
        
        import_blocks(block_numbers)
      rescue BlockNotReadyToImportError => e
        puts "#{e.message}. Stopping import."
        break
      end
    end
  end
  
  def populate_l1_rpc_results(block_numbers)
    next_start_block = block_numbers.last + 1
    next_block_numbers = (next_start_block...(next_start_block + import_batch_size * 2)).to_a
    
    blocks_to_import = block_numbers
    
    if blocks_behind > 1
      blocks_to_import += next_block_numbers.select do |num|
        num <= current_block_number
      end
    end
    
    blocks_to_import -= l1_rpc_results.keys
    
    l1_rpc_results.reverse_merge!(get_blocks_promises(blocks_to_import))
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
  
  def fetch_block_from_cache(block_number)
    block_number = [block_number, 0].max
    
    facet_block_cache.fetch(block_number)
  end
  
  def current_facet_head_block
    fetch_block_from_cache(current_max_facet_block_number)
  end
  
  def current_facet_safe_block
    fetch_block_from_cache(current_max_facet_block_number - 32)
  end
  
  def current_facet_finalized_block
    fetch_block_from_cache(current_max_facet_block_number - 64)
  end
  
  def import_blocks(block_numbers)
    puts "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current

    block_responses = l1_rpc_results.select do |block_number, _|
      block_numbers.include?(block_number)
    end.to_h.transform_values do |hsh|
      hsh.transform_values(&:value!)
    end
  
    l1_rpc_results.reject! { |block_number, _| block_responses.key?(block_number) }
    
    eth_blocks = []
    facet_blocks = []
    res = []
    
    block_numbers.each.with_index do |block_number, index|
      block_response = block_responses[block_number]
      
      block_result = block_response['block']['result']
      trace_result = block_response['trace']['result']
      receipt_result = block_response['receipts']['result']
      
      parent_eth_block = eth_block_cache[block_number - 1]
      
      if parent_eth_block && parent_eth_block.block_hash != block_result['parentHash']
        eth_block_cache.delete_if { |number, _| number >= parent_eth_block.number }
        
        facet_block_cache.delete_if do |_, facet_block|
          facet_block.eth_block_number >= parent_eth_block.number
        end
        
        return
      end
      
      eth_block = EthBlock.from_rpc_result(block_result)

      new_eth_transactions = EthTransaction.from_rpc_result(block_result, receipt_result)
              
      if trace_result
        new_eth_calls = EthCall.from_trace_result(trace_result, eth_block)
      end

      facet_block = propose_facet_block(
        eth_block,
        eth_calls: new_eth_calls,
        eth_transactions: new_eth_transactions,
        facet_block_number: current_max_facet_block_number + 1
      )
      
      facet_block = FacetBlock.from_rpc_result(facet_block)
      
      facet_block_cache[facet_block.number] = facet_block
      eth_block_cache[eth_block.number] = eth_block
      
      facet_block_threshold = current_max_facet_block_number - 65
      eth_block_threshold = current_max_eth_block_number - 65
      
      # Remove old entries from facet_block_cache
      facet_block_cache.delete_if { |number, _| number < facet_block_threshold }
      
      # Remove old entries from imported_eth_blocks
      eth_block_cache.delete_if { |number, _| number < eth_block_threshold }
      
      facet_blocks << facet_block
      eth_blocks << eth_block
      
      res << OpenStruct.new(
        facet_block: facet_block,
        transactions_imported: facet_block.in_memory_txs.length
      )
    end
  
    elapsed_time = Time.current - start
  
    blocks = res.map(&:facet_block)
    total_gas = blocks.sum(&:gas_used)
    total_transactions = res.sum(&:transactions_imported)
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
  
    [facet_blocks, eth_blocks]
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
    
    populate_l1_rpc_results([block_number])
    
    import_blocks([block_number])
  end
  
  def next_block_to_import
    next_blocks_to_import(1).first
  end
  
  def next_blocks_to_import(n)
    max_imported_block = current_max_eth_block_number
    
    start_block = max_imported_block + 1
    
    (start_block...(start_block + n)).to_a
  end
  
  def facet_txs_from_ethscriptions_in_block(eth_block, ethscriptions, facet_block)
    # results = Parallel.map_with_index(ethscriptions.sort_by(&:transaction_index), in_threads: 10) do |ethscription, idx|
    results = ethscriptions.sort_by(&:transaction_index).map.with_index do |ethscription, idx|
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
  
    results.sort_by(&:first).map(&:second)
  rescue => e
    binding.irb
    raise
  end
  
  def propose_facet_block(eth_block, eth_calls: nil, eth_transactions:, facet_block_number:)
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
    facet_txs = facet_txs.unshift(attributes_tx)

    payload = facet_txs.map(&:to_facet_payload)
    
    geth_driver.propose_block(
      payload,
      facet_block,
      current_facet_head_block,
      current_facet_safe_block,
      current_facet_finalized_block
    )
  rescue => e
    binding.irb
    raise
  end
  
  def geth_driver
    @_geth_driver ||= GethDriver
  end
end
