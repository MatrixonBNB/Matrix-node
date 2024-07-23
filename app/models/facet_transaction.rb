class FacetTransaction < ApplicationRecord
  class InvalidAddress < StandardError; end
  
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash, optional: true
  has_one :facet_transaction_receipt, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :delete
  belongs_to :eth_transaction, primary_key: :tx_hash, foreign_key: :eth_transaction_hash, optional: true
  belongs_to :ethscription, primary_key: :transaction_hash, foreign_key: :eth_transaction_hash, optional: true
  
  attr_accessor :chain_id, :eth_call
  
  FACET_TX_TYPE = 0x0F
  FACET_CHAIN_ID = 1
  FACET_INBOX_ADDRESS = "0x00000000000000000000000000000000000face7"
  
  def self.from_eth_tx_and_ethscription(ethscription, idx, legacy_receipt)
    tx = new
    tx.chain_id = FACET_CHAIN_ID
    tx.to_address = ethscription.facet_tx_to
    tx.value = 0
    tx.max_fee_per_gas = 100.gwei
    tx.gas_limit = 100e6.to_i
    tx.input = ethscription.facet_tx_input
    
    tx.eth_transaction_hash = ethscription.transaction_hash
    tx.eth_call_index = idx
    tx.from_address = legacy_receipt.from_address
    tx.eth_call = EthCall.new(
      call_index: idx
    )
    
    tx.source_hash = FacetTransaction.compute_source_hash(ethscription, tx.eth_call)
    
    tx
  end
  
  def self.from_eth_call_and_tx(eth_call, eth_tx)
    return unless eth_call.to_address == FACET_INBOX_ADDRESS
    
    hex = eth_call.input
    
    hex = Eth::Util.remove_hex_prefix hex
    type = hex[0, 2]
    
    unless type.to_i(16) == FACET_TX_TYPE
      raise Eth::Tx::TransactionTypeError, "Invalid transaction type #{type}!"
    end

    bin = Eth::Util.hex_to_bin hex[2..]
    tx = Eth::Rlp.decode bin

    unless tx.size == 6
      raise Eth::Tx::ParameterError, "Transaction missing fields!"
    end

    chain_id = Eth::Util.deserialize_big_endian_to_int tx[0]
    to = tx[1].blank? ? nil : tx[1].bytes_to_hex
    value = Eth::Util.deserialize_big_endian_to_int tx[2]
    max_gas_fee = Eth::Util.deserialize_big_endian_to_int tx[3]
    gas_limit = Eth::Util.deserialize_big_endian_to_int tx[4]
    data = tx[5].bytes_to_hex

    tx = new
    tx.chain_id = chain_id.to_i
    tx.to_address = validated_address(to)
    tx.value = value.to_i
    tx.max_fee_per_gas = max_gas_fee.to_i
    tx.gas_limit = gas_limit.to_i
    tx.input = data
    
    tx.eth_transaction = eth_tx
    tx.eth_transaction_hash = eth_call.transaction_hash
    tx.eth_call_index = eth_call.call_index
    tx.from_address = eth_call.from_address
    tx.eth_call = eth_call
    
    tx.source_hash = FacetTransaction.compute_source_hash(eth_tx, eth_call)
    
    tx
  rescue *tx_decode_errors
    nil
  end
  
  def self.compute_source_hash(eth_tx, eth_call)
    Eth::Util.keccak256(
      Eth::Util.int_to_big_endian(0) +
      Eth::Util.keccak256(
        eth_tx.block_hash.hex_to_bytes +
        Eth::Util.int_to_big_endian(eth_call.call_index)
      )
    ).bytes_to_hex
  end
  
  def to_facet_payload
    tx_data = []
    tx_data.push Eth::Util.serialize_int_to_big_endian chain_id
    tx_data.push Eth::Util.hex_to_bin source_hash
    tx_data.push Eth::Util.hex_to_bin from_address
    tx_data.push Eth::Util.hex_to_bin to_address.to_s
    tx_data.push Eth::Util.serialize_int_to_big_endian mint
    tx_data.push Eth::Util.serialize_int_to_big_endian value
    tx_data.push Eth::Util.serialize_int_to_big_endian max_fee_per_gas
    tx_data.push Eth::Util.serialize_int_to_big_endian gas_limit
    tx_data.push Eth::Util.hex_to_bin input
    tx_encoded = Eth::Rlp.encode tx_data

    tx_type = Eth::Util.serialize_int_to_big_endian FACET_TX_TYPE
    "#{tx_type}#{tx_encoded}".bytes_to_hex
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
    # Serialize the transaction fields
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
    return nil if str.blank?
    
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
