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
  
  def self.event_signature(event_name)
    "0x" + Eth::Util.bin_to_hex(Eth::Util.keccak256(event_name))
  end

  CreateEthscriptionEventSig = event_signature("ethscriptions_protocol_CreateEthscription(address,string)")

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
  
  def block_timestamp_proxy
    Struct.new(:timestamp, :number).new(block_timestamp, block_number)
  end
  
  def to_facet_tx
    return unless is_success?
    
    block_in_v2?(block_timestamp_proxy) ? to_facet_tx_v2 : to_facet_tx_v1
  end
  
  def to_facet_tx_v2
    return unless is_success?
    
    facet_tx_from_input || try_facet_tx_from_events
  end
  
  def to_facet_tx_v1
    ethscription = to_ethscription
    return unless ethscription
    
    FacetTransaction.from_ethscription(ethscription)
  end
  
  def to_ethscription
    return unless is_success?
    
    find_ethscription_from_input || find_ethscription_from_events
  end
  
  def facet_tx_from_input
    return unless to_address == FACET_INBOX_ADDRESS
    
    FacetTransaction.from_payload(
      l1_tx_origin: from_address,
      from_address: from_address,
      input: input,
      tx_hash: tx_hash,
      block_hash: block_hash
    )
  end
  
  def try_facet_tx_from_events
    facet_tx_creation_events.each do |log|
      facet_tx = FacetTransaction.from_payload(
        l1_tx_origin: from_address,
        from_address: log['address'],
        input: log['data'],
        tx_hash: tx_hash,
        block_hash: block_hash
      )
      return facet_tx if facet_tx
    end
    nil
  end
  
  def find_ethscription_from_input
    return unless to_address == Ethscription::REQUIRED_INITIAL_OWNER

    create_potentially_valid_ethscription(
      creator: from_address,
      l1_tx_origin: from_address,
      initial_owner: to_address,
      content_uri: utf8_input
    )
  end

  def find_ethscription_from_events
    ethscription_creation_events.each do |event|
      ethscription = create_ethscription_from_event(event)
      return ethscription if ethscription
    end
    nil
  end  
  
  def create_ethscription_from_event(event)
    begin
      initial_owner = Eth::Abi.decode(['address'], event['topics'].second).first
      content_uri = HexDataProcessor.clean_utf8(Eth::Abi.decode(['string'], event['data']).first)
    rescue Eth::Abi::DecodingError
      return nil
    end
    
    create_potentially_valid_ethscription(
      creator: event['address'],
      l1_tx_origin: from_address,
      initial_owner: initial_owner,
      content_uri: content_uri
    )
  end
  
  def create_potentially_valid_ethscription(attrs)
    ethscription = Ethscription.new(**ethscription_attrs(attrs).symbolize_keys)
    ethscription.valid? ? ethscription : nil
  end

  def is_success?
    status == 1
  end
  
  def ethscription_attrs(to_merge = {})
    {
      transaction_hash: tx_hash,
      block_number: block_number,
      block_blockhash: block_hash,
      transaction_index: transaction_index,
    }.merge(to_merge)
  end
  
  def facet_tx_creation_events
    logs.select do |log|
      !log['removed'] && log['topics'].length == 1 &&
        FacetLogInboxEventSig == log['topics'].first
    end.sort_by { |log| log['logIndex'].to_i(16) }
  end
  
  def ethscription_creation_events
    logs.select do |log|
      !log['removed'] && log['topics'].length == 2 &&
        CreateEthscriptionEventSig == log['topics'].first
    end.sort_by { |log| log['logIndex'].to_i(16) }
  end
  
  def utf8_input
    esip7_enabled = ChainIdManager.on_testnet? || block_number >= 19376500  
    
    HexDataProcessor.hex_to_utf8(
      input,
      support_gzip: esip7_enabled
    )
  end
  
  def facet_tx_source_hash
    FacetTransaction.compute_source_hash(
      tx_hash.hex_to_bytes,
      FacetTransaction::USER_DEPOSIT_SOURCE_DOMAIN,
    )
  end
  
  def self.to_rpc_result(eth_transactions)
    block_result = {
      'hash' => eth_transactions.first.block_hash,
      'number' => "0x" + eth_transactions.first.block_number.to_s(16),
      'baseFeePerGas' => "0x" + 1.gwei.to_s(16),
      'timestamp' => "0x" + eth_transactions.first.block_timestamp.to_s(16),
      'parentBeaconBlockRoot' => eth_transactions.first.block_hash,
      'mixHash' => eth_transactions.first.block_hash,
      'transactions' => eth_transactions.map do |tx|
        {
          'hash' => tx.tx_hash,
          'transactionIndex' => "0x" + tx.transaction_index.to_s(16),
          'input' => tx.input,
          'chainId' => "0x" + tx.chain_id.to_s(16),
          'from' => tx.from_address,
          'to' => tx.to_address
        }
      end
    }

    receipt_result = eth_transactions.map do |tx|
      {
        'transactionHash' => tx.tx_hash,
        'status' => "0x" + tx.status.to_s(16),
        'logs' => tx.logs
      }
    end
    
    [block_result, receipt_result]
  end
end
