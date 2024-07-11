module EthscriptionsImporter
  extend self
  
  class BlockNotReadyToImportError < StandardError; end
    
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
  
  def blocks_behind
    (v2_fork_block - next_block_to_import) + 1
  end
  
  def import_batch_size
    # [blocks_behind, ENV.fetch('BLOCK_IMPORT_BATCH_SIZE', 2).to_i].min
    [blocks_behind, 100].min
  end
  
  def import_blocks_until_done
    SolidityCompiler.reset_checksum
    SolidityCompiler.compile_all_legacy_files
    
    raise if in_v2?(next_block_to_import)
    
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
      
      genesis_eth_block = LegacyEthBlock.reading{ LegacyEthBlock.find_by!(block_number: genesis_block) }
      
      eth_block = EthBlock.from_legacy_eth_block(genesis_eth_block)
      eth_block.save!
      
      facet_block = FacetBlock.from_eth_block(eth_block)
      facet_block.from_rpc_response(facet_genesis_block)
      facet_block.save!
    end
  end
  
  def import_blocks(block_numbers)
    ensure_genesis_blocks
    
    logger.info "Block Importer: importing blocks #{block_numbers.join(', ')}"
    start = Time.current
    
    legacy_blocks, ethscriptions, legacy_tx_receipts = LegacyEthBlock.reading do
      [
        LegacyEthBlock.where(block_number: block_numbers).to_a,
        Ethscription.where(block_number: block_numbers).to_a.select(&:contract_transaction?),
        LegacyFacetTransactionReceipt.where(block_number: block_numbers).to_a
      ]
    end
    
    ethscriptions_by_block = ethscriptions.group_by(&:block_number)
    legacy_tx_receipts_by_block = legacy_tx_receipts.group_by(&:block_number)
    
    res = []
    
    legacy_blocks.each do |block|
      res << import_block(
        block,
        Array.wrap(ethscriptions_by_block[block.block_number]).sort_by(&:transaction_index),
        Array.wrap(legacy_tx_receipts_by_block[block.block_number]).sort_by(&:transaction_index)
      )
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
  
  def import_block(block, ethscriptions, legacy_tx_receipts, timestamp: nil)
    ActiveRecord::Base.transaction do
      eth_block = EthBlock.from_legacy_eth_block(block)

      eth_block.save!

      eth_transactions = ethscriptions.map { |e| EthTransaction.from_ethscription(e) }

      EthTransaction.import!(eth_transactions)
      
      Ethscription.import!(ethscriptions.map(&:dup))
      
      facet_block, facet_txs, facet_receipts = propose_facet_block(
        eth_block,
        ethscriptions,
        legacy_tx_receipts,
        timestamp: timestamp
      )
      
      unless legacy_tx_receipts.size == facet_receipts.size
        binding.irb
        raise "Mismatched number of legacy and facet receipts"
      end
      
      legacy_tx_receipts.each_with_index do |legacy_receipt, index|
        facet_receipt = facet_receipts[index]
        facet_status = facet_receipt.status == 1 ? 'success' : 'failure'
        
        if legacy_receipt.status != facet_status
          binding.irb
          raise "Status mismatch: Legacy receipt status #{legacy_status} does not match Facet receipt status #{facet_status}"
        end
        
        if legacy_receipt.created_contract_address && facet_receipts[index].legacy_contract_address_map.keys.exclude?(legacy_receipt.created_contract_address)
          binding.irb
          raise "Contract address mismatch"
        end
        
        if legacy_receipt.status == 'success' && legacy_receipt.logs.present? && facet_receipt.logs.blank?
          binding.irb
          raise "Log mismatch: Legacy receipt has logs but Facet receipt has none"
        end
      end
      
      OpenStruct.new(
        facet_block: facet_block,
        transactions_imported: facet_txs,
        receipts_imported: facet_receipts
      )
    end
  rescue ActiveRecord::RecordNotUnique => e
    if e.message.include?("eth_blocks") && e.message.include?("number")
      logger.info "Block Importer: Block #{block_number} already exists"
      raise ActiveRecord::Rollback
    else
      raise
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

  def facet_txs_from_ethscriptions_in_block(eth_block, ethscriptions, legacy_tx_receipts)
    ethscriptions.sort_by(&:transaction_index).map.with_index do |ethscription, idx|
      legacy_tx_receipt = legacy_tx_receipts.find { |r| r.transaction_hash == ethscription.transaction_hash }
      facet_tx = FacetTransaction.from_eth_tx_and_ethscription(ethscription, idx, legacy_tx_receipt)
      facet_tx.mint = 500.ether
      
      raise unless facet_tx.present?
      
      facet_tx
    end
  end
  
  def propose_facet_block(eth_block, ethscriptions, legacy_tx_receipts, timestamp: nil)
    facet_block = FacetBlock.from_eth_block(eth_block, timestamp: timestamp)
    
    facet_txs = facet_txs_from_ethscriptions_in_block(
      eth_block,
      ethscriptions,
      legacy_tx_receipts
    )
        
    payload = facet_txs.sort_by(&:eth_call_index).map(&:to_facet_payload)
    
    response = geth_driver.propose_block(
      payload,
      facet_block
    )

    geth_block = geth_driver.client.call("eth_getBlockByNumber", [response['blockNumber'], true])
    
    facet_block.from_rpc_response(geth_block)

    facet_block.save!
    
    receipts_data = geth_driver.client.call("eth_getBlockReceipts", [response['blockNumber']])
    receipts_data_by_hash = receipts_data.index_by { |receipt| receipt['transactionHash'] }
    
    facet_txs_by_source_hash = facet_txs.index_by(&:source_hash)
    
    receipts = []
    
    geth_block['transactions'].each do |tx|
      receipt_details = receipts_data_by_hash[tx['hash']]
      
      facet_tx = facet_txs_by_source_hash[tx['sourceHash']]
      raise unless facet_tx

      facet_tx.assign_attributes(
        tx_hash: tx['hash'],
        block_hash: response['blockHash'],
        block_number: response['blockNumber'].to_i(16),
        transaction_index: receipt_details['transactionIndex'].to_i(16),
        deposit_receipt_version: tx['depositReceiptVersion'].to_i(16),
        gas: tx['gas'].to_i(16),
        tx_type: tx['type']
      )
      
      facet_receipt = FacetTransactionReceipt.new(
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
      
      # Pair the receipt with its legacy counterpart
      legacy_receipt = legacy_tx_receipts.find { |legacy_tx| legacy_tx.transaction_hash == facet_tx.eth_transaction_hash }
      facet_receipt.legacy_receipt = legacy_receipt
      
      receipts << facet_receipt
    end
    
    FacetTransaction.import!(facet_txs)
    
    FacetTransactionReceipt.import!(receipts)
    
    [facet_block, facet_txs, receipts]
  rescue => e
    binding.irb
    raise
  end
  
  def geth_driver
    @_geth_driver ||= GethDriver
  end
  
  def facet_chain_id
    FacetTransaction::FACET_CHAIN_ID
  end
end
