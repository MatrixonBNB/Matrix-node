class FacetTransactionReceipt < ApplicationRecord
  include Memery
  
  belongs_to :facet_transaction, primary_key: :tx_hash, foreign_key: :transaction_hash
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
  
  before_validation :set_legacy_contract_address_map
  
  attr_accessor :legacy_receipt
  
  def set_legacy_contract_address_map
    unless legacy_receipt
      self.legacy_contract_address_map[calculate_legacy_contract_address] = contract_address
      self.legacy_contract_address_map.compact!
      return
    end
    
    self.legacy_contract_address_map[legacy_receipt.created_contract_address] = contract_address
    
    our_pair_created = decoded_legacy_logs.detect do |log|
      log['event'] == 'PairCreated'
    end
    
    if our_pair_created
      their_pair_created = legacy_receipt.logs.detect{|i| i['event'] == 'PairCreated'}
      
      if their_pair_created
        self.legacy_contract_address_map[their_pair_created['data']['pair']] = our_pair_created['data']['pair']
      end
    end
    
    self.legacy_contract_address_map.compact!
  end
  
  def trace
    process_trace(GethDriver.trace_transaction(transaction_hash))
  end
  
  def process_trace(trace)
    trace['calls'].each do |call|
      process_call(call)
    end
  end
  
  def process_call(call)
    if call['to'] == '0x000000000000000000636f6e736f6c652e6c6f67'
      data = call['input'][10..-1]
      decoded_data = Eth::Abi.decode(['string'], [data].pack('H*')) rescue [data]
      decoded_log = decoded_data.first
      call['console.log'] = decoded_log
      call.delete('input')
      call.delete('gas')
      call.delete('gasUsed')
      call.delete('to')
      call.delete('type')
    end
  
    # Recursively process nested calls
    if call['calls']
      call['calls'].each do |sub_call|
        process_call(sub_call)
      end
    end
  end
  
  def decoded_legacy_logs
    logs.map do |log|
      implementation_address = Ethscription.get_implementation(log['address'])
      
      implementation_name = Ethscription.local_from_predeploy(implementation_address) rescue binding.irb
      impl = EVMHelpers.compile_contract(implementation_name)
      begin
        impl.parent.decode_log(log)
      rescue Eth::Contract::UnknownEvent => e
        impl = EVMHelpers.compile_contract("legacy/ERC1967Proxy")
        impl.parent.decode_log(log)
      rescue => e
        binding.irb
      end
    end
  end
  memoize :decoded_legacy_logs
  
  def calculate_legacy_contract_address
    return unless contract_address
    
    current_nonce = FacetTransactionReceipt
      .where(from_address: from_address)
      .where('block_number < ? OR (block_number = ? AND transaction_index < ?)', block_number, block_number, transaction_index)
      .count
    
    rlp_encoded = Eth::Rlp.encode([
      Integer(from_address, 16),
      current_nonce,
      "facet"
    ])
    
    hash = Eth::Util.keccak256(rlp_encoded).bytes_to_unprefixed_hex
    "0x" + hash.last(40)
  end
end
