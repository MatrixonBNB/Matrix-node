class EthTransaction < T::Struct
  include SysConfig
  
  const :block_hash, String
  const :block_number, Integer
  const :block_timestamp, Integer
  const :tx_hash, String
  const :transaction_index, Integer
  const :input, T.nilable(String)
  const :chain_id, T.nilable(Integer)
  const :from_address, T.nilable(String)
  const :to_address, T.nilable(String)
  const :status, T.nilable(Integer)
  const :logs, T::Array[T.untyped], default: []
  const :eth_block, T.nilable(EthBlock)
  const :facet_transactions, T::Array[FacetTransaction], default: []
  
  FacetLogInboxEventSig = "0x00000000000000000000000000000000000000000000000000000000000face7"

  def self.from_rpc_result(block_result, receipt_result)
    block_hash = block_result['hash']
    block_number = block_result['number'].to_i(16)
    
    indexed_receipts = receipt_result.index_by{|el| el['transactionHash']}
    
    block_result['transactions'].map do |tx|
      current_receipt = indexed_receipts[tx['hash']]
      
      EthTransaction.new(
        block_hash: block_hash,
        block_number: block_number,
        block_timestamp: block_result['timestamp'].to_i(16),
        tx_hash: tx['hash'],
        transaction_index: tx['transactionIndex'].to_i(16),
        input: tx['input'],
        chain_id: tx['chainId']&.to_i(16),
        from_address: tx['from'],
        to_address: tx['to'],
        status: current_receipt['status'].to_i(16),
        logs: current_receipt['logs'],
      )
    end
  end
  
  def self.facet_txs_from_rpc_results(block_results, receipt_results)
    eth_txs = from_rpc_result(block_results, receipt_results)
    eth_txs.sort_by(&:transaction_index).map(&:to_facet_tx).compact
  end
  
  def to_facet_tx
    return unless is_success?
    
    facet_tx_from_input || try_facet_tx_from_events
  end
  
  def facet_tx_from_input
    return unless to_address == FACET_INBOX_ADDRESS
    
    FacetTransaction.from_payload(
      contract_initiated: false,
      from_address: from_address,
      input: input,
      tx_hash: tx_hash,
      block_hash: block_hash
    )
  end
  
  def try_facet_tx_from_events
    facet_tx_creation_events.each do |log|
      facet_tx = FacetTransaction.from_payload(
        contract_initiated: true,
        from_address: log['address'],
        input: log['data'],
        tx_hash: tx_hash,
        block_hash: block_hash
      )
      return facet_tx if facet_tx
    end
    nil
  end
  
  def is_success?
    status == 1
  end
  
  def facet_tx_creation_events
    logs.select do |log|
      !log['removed'] && log['topics'].length == 1 &&
        FacetLogInboxEventSig == log['topics'].first
    end.sort_by { |log| log['logIndex'].to_i(16) }
  end
  
  def facet_tx_source_hash
    tx_hash
  end
end
