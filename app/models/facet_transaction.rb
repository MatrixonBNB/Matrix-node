class FacetTransaction < ApplicationRecord
  class InvalidAddress < StandardError; end
  
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash, optional: true
  has_one :facet_transaction_receipt, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  belongs_to :eth_transaction, primary_key: :tx_hash, foreign_key: :eth_transaction_hash, optional: true
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :eth_transaction_hash, optional: true
  
  attr_accessor :chain_id, :eth_call
  
  FACET_TX_TYPE = 70
  FACET_INBOX_ADDRESS = "0x00000000000000000000000000000000000face7"
  
  DEPOSIT_TX_TYPE = 0x7E
  
  USER_DEPOSIT_SOURCE_DOMAIN = 0
  L1_INFO_DEPOSIT_SOURCE_DOMAIN = 1
  
  SYSTEM_ADDRESS = "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001"
  L1_INFO_ADDRESS = "0x4200000000000000000000000000000000000015"
  
  PER_TX_GAS_LIMIT = 30_000_000
  
  def within_gas_limit?
    gas_limit <= PER_TX_GAS_LIMIT
  end
  
  def self.current_chain_id(network = ENV.fetch('ETHEREUM_NETWORK'))
    if ENV['CUSTOM_CHAIN_ID']
      return ENV['CUSTOM_CHAIN_ID'].to_i
    end
    
    return 0xface7 if network == "eth-mainnet"
    return 0xface7a if network == "eth-sepolia"
    
    raise "Invalid network: #{network}"
  end
  
  def self.from_eth_tx_and_ethscription(
    ethscription,
    idx,
    eth_block,
    tx_count_in_block,
    facet_block
  )
    tx = new
    tx.facet_block = facet_block
    tx.chain_id = current_chain_id
    tx.to_address = ethscription.facet_tx_to
    tx.value = 0
    tx.input = ethscription.facet_tx_input
    
    tx.eth_transaction_hash = ethscription.transaction_hash
    tx.eth_call_index = idx
    tx.from_address = ethscription.creator
    tx.eth_call = EthCall.new(
      call_index: idx
    )
    
    payload = [
      ethscription.block_hash.hex_to_bytes,
      ethscription.transaction_hash.hex_to_bytes,
      0.zpad(32)
    ].join
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      payload,
      USER_DEPOSIT_SOURCE_DOMAIN
    )
    
    user_current_balance = TransactionHelper.balance(tx.from_address)
    next_block_base_fee = facet_block.calculated_base_fee_per_gas
    
    eth_gas_used = ethscription.gas_used
    eth_base_fee = eth_block.base_fee_per_gas
    mint_amount = eth_gas_used * eth_base_fee
    
    user_next_balance = user_current_balance + mint_amount
    
    block_gas_limit = FacetBlock::GAS_LIMIT
    per_tx_avg_gas_limit = block_gas_limit / (tx_count_in_block + 1) # Attributes tx
    
    tx.max_fee_per_gas = next_block_base_fee
    tx.gas_limit = [user_next_balance / tx.max_fee_per_gas, per_tx_avg_gas_limit].min
    tx.mint = mint_amount
    
    tx
  end
  
  def self.calculate_calldata_cost(hex_string)
    bytes = hex_string.hex_to_bytes
    zero_count = bytes.count("\x00")
    non_zero_count = bytes.size - zero_count
    
    zero_count * 4 + non_zero_count * 16
  end
  
  def self.calculate_mint_amount(input_data, base_fee)
    calldata_cost = calculate_calldata_cost(input_data)
    calldata_cost * base_fee * 1024
  end
  
  def self.from_eth_transactions_in_block(eth_block, eth_transactions, eth_calls, facet_block)
    facet_txs = eth_calls.map do |call|
      next unless call.to_address == FACET_INBOX_ADDRESS
      next if call.error.present?
      
      eth_tx = eth_transactions.detect { |tx| tx.tx_hash == call.transaction_hash }
      
      facet_tx = FacetTransaction.from_eth_call_and_tx(call, eth_tx)
      
      facet_tx&.mint = calculate_mint_amount(call.input, eth_block.base_fee_per_gas)
      
      facet_tx&.facet_block = facet_block
      
      facet_tx
    end.flatten.compact
    
    facet_txs = facet_txs.sort_by(&:eth_call_index).each_with_object([[], 0]) do |tx, (selected, total_gas)|
      if total_gas + tx.gas_limit <= FacetBlock::GAS_LIMIT
        selected << tx
        total_gas += tx.gas_limit
      end
    end.first
    
    facet_txs
  end
  
  def self.from_eth_call_and_tx(eth_call, eth_tx)
    return unless eth_call.to_address == FACET_INBOX_ADDRESS
    return if eth_call.error.present?
    
    hex = eth_call.input
    
    hex = Eth::Util.remove_hex_prefix hex
    type = hex[0, 2]
    
    unless type.to_i(16) == FACET_TX_TYPE
      raise Eth::Tx::TransactionTypeError, "Invalid transaction type #{type}!"
    end

    bin = Eth::Util.hex_to_bin hex[2..]
    tx = Eth::Rlp.decode bin

    # So people can add "extra data" to burn more gas
    # unless tx.size == 6
    #   raise Eth::Tx::ParameterError, "Transaction missing fields!"
    # end

    chain_id = Eth::Util.deserialize_big_endian_to_int tx[0]
    
    unless chain_id == current_chain_id
      raise Eth::Tx::ParameterError, "Invalid chain ID #{chain_id}!"
    end
    
    to = tx[1].blank? ? nil : tx[1].bytes_to_hex
    value = Eth::Util.deserialize_big_endian_to_int tx[2]
    max_gas_fee = tx[3].blank? ? nil : Eth::Util.deserialize_big_endian_to_int(tx[3])
    gas_limit = Eth::Util.deserialize_big_endian_to_int tx[4]
    data = tx[5].bytes_to_hex

    tx = new
    tx.chain_id = chain_id.to_i
    tx.to_address = validated_address(to)
    tx.value = value.to_i
    tx.max_fee_per_gas = max_gas_fee.to_i
    tx.gas_limit = gas_limit.to_i
    tx.input = data
    
    return unless tx.within_gas_limit?
    
    tx.eth_transaction = eth_tx
    tx.eth_transaction_hash = eth_call.transaction_hash
    tx.eth_call_index = eth_call.call_index
    tx.from_address = eth_call.from_address
    tx.eth_call = eth_call
    
    payload = [
      eth_tx.block_hash.hex_to_bytes,
      eth_call.transaction_hash.hex_to_bytes,
      eth_call.order_in_tx.zpad(32)
    ].join
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      payload,
      USER_DEPOSIT_SOURCE_DOMAIN,
    )
    
    tx
  rescue *tx_decode_errors, InvalidAddress => e
    nil
  end
  
  def self.l1_attributes_tx_from_blocks(eth_block, facet_block)
    calldata = L1AttributesTxCalldata.build(
      timestamp: eth_block.timestamp,
      number: eth_block.number,
      base_fee: eth_block.base_fee_per_gas,
      hash: eth_block.block_hash
    )
    
    tx = new
    tx.chain_id = current_chain_id
    tx.to_address = L1_INFO_ADDRESS
    tx.value = 0
    tx.mint = 0
    tx.max_fee_per_gas = 0
    tx.gas_limit = 1_000_000
    tx.input = calldata
    tx.from_address = SYSTEM_ADDRESS
    
    tx.facet_block = facet_block
    
    payload = [
      eth_block.block_hash.hex_to_bytes,
      0.zpad(32)
    ].join
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      payload,
      L1_INFO_DEPOSIT_SOURCE_DOMAIN
    )
    
    tx
  end
  
  def self.compute_source_hash(payload, source_domain)
    Eth::Util.keccak256(
      Eth::Util.zpad_int(source_domain, 32) +
      Eth::Util.keccak256(payload)
    ).bytes_to_hex
  end
  
  def to_facet_payload
    if max_fee_per_gas == 0 || max_fee_per_gas > facet_block.calculated_base_fee_per_gas
      calculated_max_fee_per_gas = facet_block.calculated_base_fee_per_gas
    else
      calculated_max_fee_per_gas = max_fee_per_gas
    end
    
    tx_data = []
    tx_data.push Eth::Util.hex_to_bin source_hash
    tx_data.push Eth::Util.hex_to_bin from_address
    tx_data.push Eth::Util.hex_to_bin to_address.to_s
    tx_data.push Eth::Util.serialize_int_to_big_endian mint
    tx_data.push Eth::Util.serialize_int_to_big_endian value
    tx_data.push Eth::Util.serialize_int_to_big_endian calculated_max_fee_per_gas
    tx_data.push Eth::Util.serialize_int_to_big_endian gas_limit
    tx_data.push ''
    tx_data.push Eth::Util.hex_to_bin input
    tx_encoded = Eth::Rlp.encode tx_data

    tx_type = Eth::Util.serialize_int_to_big_endian DEPOSIT_TX_TYPE
    "#{tx_type}#{tx_encoded}".bytes_to_hex
  end
  
  def estimate_gas
    # Should use this unless it fails
    
    _input = input.starts_with?("0x") ? input : "0x" + input
    
    geth_params = {
      from: from_address,
      to: to_address,
      data: _input
    }
    
    TransactionHelper.client.call("eth_estimateGas", [geth_params, "latest"])
  rescue => e
    binding.irb
    raise
  end
  
  def self.tx_decode_errors
    [
      Eth::Rlp::DecodingError,
      Eth::Tx::TransactionTypeError,
      Eth::Tx::ParameterError,
      Eth::Tx::DecoderError
    ]
  end
  
  def to_eth_payload
    chain_id_bin = Eth::Util.serialize_int_to_big_endian(chain_id)
    to_bin = Eth::Util.hex_to_bin(to_address.to_s)
    value_bin = Eth::Util.serialize_int_to_big_endian(value)
    max_gas_fee_bin = Eth::Util.serialize_int_to_big_endian(max_fee_per_gas)
    gas_limit_bin = Eth::Util.serialize_int_to_big_endian(gas_limit)
    data_bin = Eth::Util.hex_to_bin(input)

    # Encode the fields using RLP
    rlp_encoded = Eth::Rlp.encode([chain_id_bin, to_bin, value_bin, max_gas_fee_bin, gas_limit_bin, data_bin])

    # Add the transaction type prefix and convert to hex
    hex_payload = Eth::Util.bin_to_prefixed_hex([FACET_TX_TYPE].pack('C') + rlp_encoded)

    hex_payload
  end
  
  def self.validated_address(str)
    if str.nil? || str.empty?
      return nil
    end
    
    if str.match?(/\A0x[0-9a-f]{40}\z/)
      str
    else
      raise InvalidAddress, "Invalid address #{str}!"
    end
  end
  
  def trace
    GethDriver.trace_transaction(tx_hash)
  end
end
