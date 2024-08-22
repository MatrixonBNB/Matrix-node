class EthTransaction < ApplicationRecord
  belongs_to :eth_block, primary_key: :block_hash, foreign_key: :block_hash
  has_many :eth_calls, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  has_many :facet_transactions, -> { order(eth_call_index: :asc) },
    primary_key: :tx_hash, foreign_key: :eth_transaction_hash, dependent: :destroy
    
  attr_accessor :initialized_ethscription
  
  def self.from_rpc_result(block_result, receipt_result = nil)
    block_hash = block_result['hash']
    block_number = block_result['number'].to_i(16)
    
    if receipt_result.present?
      indexed_receipts = receipt_result.index_by{|el| el['transactionHash']}
    end
    
    block_result['transactions'].map do |tx|
      tx = EthTransaction.new(
        block_hash: block_hash,
        block_number: block_number,
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
      
      if indexed_receipts.present?
        current_receipt = indexed_receipts[tx.tx_hash]
        
        tx.status = current_receipt['status'].to_i(16)
        tx.logs = current_receipt['logs']
        tx.gas_used = current_receipt['gasUsed'].to_i(16)
      end
      
      tx
    end
  end
  
  def self.from_ethscription(ethscription)
    EthTransaction.new(
      block_hash: ethscription.block_blockhash,
      block_number: ethscription.block_number,
      tx_hash: ethscription.transaction_hash,
      transaction_index: ethscription.transaction_index,
      from_address: ethscription.creator,
      to_address: ethscription.initial_owner,
      input: ethscription.content_uri,
      gas: ethscription.gas_used,
    )
  end
  
  def utf8_input
    HexDataProcessor.hex_to_utf8(
      input,
      support_gzip: self.class.esip7_enabled?(block_number)
    )
  end
  
  def self.event_signature(event_name)
    "0x" + Eth::Util.bin_to_hex(Eth::Util.keccak256(event_name))
  end
  
  def ethscription_creation_events
    logs.select do |log|
      !log['removed'] && CreateEthscriptionEventSig == log['topics'].first
    end.sort_by { |log| log['logIndex'].to_i(16) }
  end
    
  def self.esip7_enabled?(block_number)
    on_testnet? || block_number >= 19376500
  end
  
  CreateEthscriptionEventSig = event_signature("ethscriptions_protocol_CreateEthscription(address,string)")
  
  def init_ethscription_from_input
    unless to_address == Ethscription::REQUIRED_INITIAL_OWNER
      return
    end
    
    attrs = ethscription_attrs({
      creator: from_address,
      initial_owner: to_address,
      content_uri: utf8_input,
    })
    
    potentially_valid = Ethscription.new(**attrs.symbolize_keys)
    
    init_if_valid_and_no_ethscription_initialized(potentially_valid)
  end
  
  def init_ethscription_from_events
    ethscription_creation_events.each do |creation_event|
      next if creation_event['topics'].length != 2
    
      begin
        initial_owner = Eth::Abi.decode(['address'], creation_event['topics'].second).first
        
        content_uri_data = Eth::Abi.decode(['string'], creation_event['data']).first
        content_uri = HexDataProcessor.clean_utf8(content_uri_data)
      rescue Eth::Abi::DecodingError
        next
      end
         
      attrs = ethscription_attrs({
        creator: creation_event['address'],
        initial_owner: initial_owner,
        content_uri: content_uri
      })
      
      potentially_valid = Ethscription.new(**attrs.symbolize_keys)
      
      init_if_valid_and_no_ethscription_initialized(potentially_valid)
    end
  end
  
  def init_ethscription
    return unless status == 1
    init_ethscription_from_input
    init_ethscription_from_events
    
    initialized_ethscription
  end
  
  def init_if_valid_and_no_ethscription_initialized(potentially_valid)
    return if initialized_ethscription.present?
    return unless potentially_valid.valid?
    
    self.initialized_ethscription = potentially_valid
    initialized_ethscription
  end
  
  def ethscription_attrs(to_merge = {})
    {
      transaction_hash: tx_hash,
      block_number: block_number,
      block_blockhash: block_hash,
      transaction_index: transaction_index,
      gas_used: gas_used
    }.merge(to_merge)
  end
  
  def self.on_testnet?
    ENV['ETHEREUM_NETWORK'] != "eth-mainnet"
  end
end
