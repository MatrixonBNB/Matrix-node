class FacetTransaction < ApplicationRecord
  include SysConfig
  class InvalidAddress < StandardError; end
  class TxOutsideGasLimit < StandardError; end
  
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash, optional: true
  has_one :facet_transaction_receipt, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  
  attr_accessor :chain_id, :l1_tx_origin, :l1_calldata_gas_used, :contract_initiated, :ethscription
  
  FACET_TX_TYPE = 0x46
  DEPOSIT_TX_TYPE = 0x7E
  
  USER_DEPOSIT_SOURCE_DOMAIN = 0
  L1_INFO_DEPOSIT_SOURCE_DOMAIN = 1
  UPGRADE_DEPOSITED_SOURCE_DOMAIN = 2
  
  SYSTEM_ADDRESS = "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001"
  L1_INFO_ADDRESS = "0x4200000000000000000000000000000000000015"
  
  def within_gas_limit?
    gas_limit <= PER_L2_TX_GAS_LIMIT
  end
  
  def self.from_ethscription(ethscription)
    tx = new
    tx.ethscription = ethscription
    tx.chain_id = ChainIdManager.current_l2_chain_id
    tx.to_address = ethscription.facet_tx_to
    tx.value = 0
    tx.input = ethscription.facet_tx_input
    
    tx.eth_transaction_hash = ethscription.transaction_hash
    tx.from_address = ethscription.creator
    
    tx.contract_initiated = ethscription.contract_initiated?
    
    # It has a burn function
    l2_to_l1_message_passer = "0x4200000000000000000000000000000000000016"
    tx.l1_tx_origin = l2_to_l1_message_passer
    
    payload = [
      ethscription.block_hash.hex_to_bytes,
      ethscription.transaction_hash.hex_to_bytes,
      0.zpad(32)
    ].join
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      payload,
      USER_DEPOSIT_SOURCE_DOMAIN
    )
    
    tx.max_fee_per_gas = 2 ** 256 - 1
    
    tx
  end
  
  def assign_gas_limit_from_tx_count_in_block(tx_count_in_block)
    block_gas_limit = SysConfig.block_gas_limit(facet_block)
    self.gas_limit = block_gas_limit / (tx_count_in_block + 1) # Attributes tx
  end
  
  def self.calculate_calldata_cost(hex_string, contract_initiated:)
    bytes = hex_string.hex_to_bytes
    zero_count = bytes.count("\x00")
    non_zero_count = bytes.bytesize - zero_count
    
    if contract_initiated
      bytes.bytesize * 8
    else
      zero_count * 4 + non_zero_count * 16
    end
  end
  
  def self.from_payload(
    l1_tx_origin:,
    from_address:,
    input:,
    tx_hash:,
    block_hash:
  )
    hex = input
    
    hex = Eth::Util.remove_hex_prefix hex
    type = hex[0, 2]
    
    unless type.to_i(16) == FACET_TX_TYPE
      raise Eth::Tx::TransactionTypeError, "Invalid transaction type #{type}!"
    end

    bin = Eth::Util.hex_to_bin hex[2..]
    tx = Eth::Rlp.decode bin

    # So people can add "extra data" to burn more gas
    unless [6, 7].include?(tx.size)
      raise Eth::Tx::ParameterError, "Transaction missing fields!"
    end

    chain_id = Eth::Util.deserialize_big_endian_to_int(tx[0])
    
    unless chain_id == ChainIdManager.current_l2_chain_id
      raise Eth::Tx::ParameterError, "Invalid chain ID #{chain_id}!"
    end
    
    to = tx[1].length.zero? ? nil : tx[1].bytes_to_hex
    value = Eth::Util.deserialize_big_endian_to_int(tx[2])
    max_gas_fee = Eth::Util.deserialize_big_endian_to_int(tx[3])
    gas_limit = Eth::Util.deserialize_big_endian_to_int(tx[4])
    data = tx[5].bytes_to_hex

    tx = new
    tx.chain_id = clamp_uint(chain_id, 256)
    tx.to_address = validated_address(to)
    tx.value = clamp_uint(value, 256)
    tx.max_fee_per_gas = clamp_uint(max_gas_fee, 256)
    tx.gas_limit = clamp_uint(gas_limit, 64)
    tx.input = data
    
    unless tx.within_gas_limit?
      raise TxOutsideGasLimit, "Transaction outside gas limit!"
    end
    
    tx.eth_transaction_hash = tx_hash
    tx.from_address = from_address
    tx.l1_tx_origin = l1_tx_origin
    
    tx.contract_initiated = tx.l1_tx_origin != tx.from_address
    
    tx.l1_calldata_gas_used = calculate_calldata_cost(
      input,
      contract_initiated: tx.contract_initiated
    )
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      tx_hash.hex_to_bytes,
      USER_DEPOSIT_SOURCE_DOMAIN,
    )
    
    tx
  rescue *tx_decode_errors, InvalidAddress, TxOutsideGasLimit => e
    nil
  end
  
  def self.l1_attributes_tx_from_blocks(facet_block)
    calldata = L1AttributesTxCalldata.build(
      timestamp: facet_block.eth_block_timestamp,
      number: facet_block.eth_block_number,
      base_fee: facet_block.eth_block_base_fee_per_gas,
      hash: facet_block.eth_block_hash,
      sequence_number: facet_block.sequence_number
    )
    
    tx = new
    tx.chain_id = ChainIdManager.current_l2_chain_id
    tx.to_address = L1_INFO_ADDRESS
    tx.value = 0
    tx.mint = 0
    tx.max_fee_per_gas = 0
    tx.gas_limit = 1_000_000
    tx.input = calldata
    tx.from_address = SYSTEM_ADDRESS
    
    tx.facet_block = facet_block
    
    payload = [
      facet_block.eth_block_hash.hex_to_bytes,
      facet_block.sequence_number.zpad(32)
    ].join
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      payload,
      L1_INFO_DEPOSIT_SOURCE_DOMAIN
    )
    
    tx
  end
  
  def self.v1_to_v2_migration_tx_from_block(facet_block, batch_number:)
    unless SysConfig.is_first_v2_block?(facet_block)
      raise "Invalid block number #{facet_block.number}!"
    end
    
    function_selector = Eth::Util.keccak256('executeMigration()').first(4).bytes_to_hex
    migration_manager_address = "0x" + Eth::Util.keccak256("migration manager").bytes_to_hex.last(40)
    msg_sender = "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001"
    
    upgrade_intent = "emit events required to complete v1 to v2 migration batch ##{batch_number}"

    tx = new
    tx.chain_id = ChainIdManager.current_l2_chain_id
    tx.to_address = migration_manager_address
    tx.value = 0
    tx.mint = 0
    tx.max_fee_per_gas = 0
    tx.gas_limit = 100e9.to_i
    tx.input = function_selector
    tx.from_address = msg_sender
    
    tx.facet_block = facet_block
    
    tx.source_hash = FacetTransaction.compute_source_hash(
      Eth::Util.keccak256(upgrade_intent),
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
    tx_data = []
    tx_data.push(Eth::Util.hex_to_bin(source_hash))
    tx_data.push(Eth::Util.hex_to_bin(l1_tx_origin.to_s))
    tx_data.push(Eth::Util.hex_to_bin(calculated_from_address))
    tx_data.push(Eth::Util.hex_to_bin(to_address.to_s))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(mint))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(value))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(max_fee_per_gas))
    tx_data.push(Eth::Util.serialize_int_to_big_endian(gas_limit))
    tx_data.push('')
    tx_data.push(Eth::Util.hex_to_bin(input))
    tx_encoded = Eth::Rlp.encode(tx_data)

    tx_type = Eth::Util.serialize_int_to_big_endian(DEPOSIT_TX_TYPE)
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
  
  def self.validated_address(str)
    if str.nil? || str.match?(/\A0x[0-9a-f]{40}\z/)
      str
    else
      raise InvalidAddress, "Invalid address #{str}!"
    end
  end
  
  def trace
    GethDriver.trace_transaction(tx_hash)
  end
  
  def calculated_from_address
    if contract_initiated
      AddressAliasHelper.apply_l1_to_l2_alias(from_address)
    else
      from_address
    end
  end
  
  def self.clamp_uint(input, max_bits)
    [input.to_i, 2 ** max_bits - 1].min
  end
end
