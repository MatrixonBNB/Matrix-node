class FacetTransaction < ApplicationRecord
  belongs_to :facet_block, primary_key: :block_hash, foreign_key: :block_hash
  has_one :facet_transaction_receipt, primary_key: :tx_hash, foreign_key: :transaction_hash, dependent: :destroy
  belongs_to :eth_transaction, primary_key: :tx_hash, foreign_key: :eth_transaction_hash
  
  attr_accessor :chain_id, :eth_call
  
  TYPE_FACET = 0x0F
  
  def to_tx_payload
    # Serialize the transaction fields
    chain_id_bin = Eth::Util.serialize_big_endian_to_int(chain_id)
    to_bin = Eth::Util.hex_to_bin(to_address)
    value_bin = Eth::Util.serialize_big_endian_to_int(value)
    max_gas_fee_bin = Eth::Util.serialize_big_endian_to_int(max_fee_per_gas)
    gas_limit_bin = Eth::Util.serialize_big_endian_to_int(gas_limit)
    data_bin = Eth::Util.hex_to_bin(input)

    # Encode the fields using RLP
    rlp_encoded = Eth::Rlp.encode([chain_id_bin, to_bin, value_bin, max_gas_fee_bin, gas_limit_bin, data_bin])

    # Add the transaction type prefix and convert to hex
    hex_payload = Eth::Util.bin_to_hex([TYPE_FACET].pack('C') + rlp_encoded)

    hex_payload
  end
  
  def self.from_tx_payload(hex)
    hex = Eth::Util.remove_hex_prefix hex
    type = hex[0, 2]
    
    unless type.to_i(16) == TYPE_FACET
      raise Eth::Tx::TransactionTypeError, "Invalid transaction type #{type}!"
    end

    bin = Eth::Util.hex_to_bin hex[2..]
    tx = Eth::Rlp.decode bin

    unless tx.size == 6
      raise Eth::Tx::ParameterError, "Transaction missing fields!"
    end

    chain_id = Eth::Util.deserialize_big_endian_to_int tx[0]
    to = Eth::Util.bin_to_hex tx[1]
    value = Eth::Util.deserialize_big_endian_to_int tx[2]
    max_gas_fee = Eth::Util.deserialize_big_endian_to_int tx[3]
    gas_limit = Eth::Util.deserialize_big_endian_to_int tx[4]
    data = tx[5].bytes_to_hex

    tx = new
    tx.chain_id = chain_id.to_i
    tx.to_address = to.to_s
    tx.value = value.to_i
    tx.max_fee_per_gas = max_gas_fee.to_i
    tx.gas_limit = gas_limit.to_i
    tx.input = data
    tx
  end
  
  def to_payload
    raise unless eth_call
    
    computed_from = eth_call.parent_call_index.nil? ?
      from_address :
      Eth::Tx::Deposit.alias_address(from_address)
    
    Eth::Tx::Deposit.new(
      source_hash: source_hash,
      from: computed_from,
      to: to_address,
      mint: mint,
      value: value,
      gas_limit: gas_limit,
      # max_fee_per_gas
      is_system_tx: false,
      data: input,
    ).encoded.bytes_to_hex
  end
end
