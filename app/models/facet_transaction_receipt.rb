class FacetTransactionReceipt < ApplicationRecord
  belongs_to :facet_transaction, primary_key: :tx_hash, foreign_key: :transaction_hash
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
  
  before_validation :set_legacy_contract_address
  
  def set_legacy_contract_address
    self.legacy_contract_address = calculate_legacy_contract_address
  end
  
  def decoded_legacy_logs
    logs.map do |log|
      implementation_address = TransactionHelper.static_call(
        contract: 'legacy/ERC1967Proxy',
        address: log['address'],
        function: '__getImplementation',
        args: []
      ) rescue binding.irb
      
      implementation_name = Ethscription.local_from_predeploy(implementation_address)
      impl = EVMHelpers.compile_contract(implementation_name)
      begin
        impl.parent.decode_log(log)
      rescue Eth::Contract::UnknownEvent => e
        EVMHelpers.compile_contract("legacy/ERC1967Proxy").parent.decode_log(log)
      rescue => e
        binding.irb
      end
    end
  end
  
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
