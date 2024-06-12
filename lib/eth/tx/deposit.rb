# Provides the {Eth} module.
module Eth

  # Provides the `Tx` module supporting various transaction types.
  module Tx

    # Provides support for Deposit transactions utilizing EIP-2718
    # types and envelopes.
    class Deposit
      TYPE_DEPOSIT = 0x7E
      
      # The source hash, uniquely identifies the origin of the deposit.
      attr_reader :source_hash

      # The address of the sender account.
      attr_reader :from

      # The address of the recipient account, or the null address if it's a contract creation.
      attr_reader :to

      # The ETH value to mint on L2.
      attr_reader :mint

      # The ETH value to send to the recipient account.
      attr_reader :value

      # The gas limit for the L2 transaction.
      attr_reader :gas_limit

      # Indicates if the transaction does not interact with the L2 block gas pool.
      attr_reader :is_system_tx

      # The transaction data payload.
      attr_reader :payload

      # The transaction type.
      attr_reader :type
      
      # Create a deposit transaction payload object that
      # can be prepared for envelope, signature, and broadcast.
      #
      # @param params [Hash] all necessary transaction fields.
      # @option params [String] :source_hash the source hash.
      # @option params [Eth::Address] :from the sender address.
      # @option params [Eth::Address] :to the receiver address.
      # @option params [Integer] :mint the value to mint.
      # @option params [Integer] :value the transaction value.
      # @option params [Integer] :gas_limit the gas limit.
      # @option params [Boolean] :is_system_tx indicates if the transaction is a system transaction.
      # @option params [String] :data the transaction data payload.
      def initialize(params)
        fields = { r: 0, s: 0 }.merge(params)

        # populate optional fields with serializable empty values
        
        fields[:from] = fields[:from].nil? ? nil : "0x" + Tx.sanitize_address(fields[:from]).downcase
        fields[:to] = fields[:to].nil? ? nil : "0x" + Tx.sanitize_address(fields[:to]).downcase
        fields[:value] = Tx.sanitize_amount(fields[:value])
        fields[:data] = Tx.sanitize_data(fields[:data])

        # ensure sane values for all mandatory fields
        # fields = Tx.validate_deposit_params(fields)

        # populate class attributes
        @source_hash = fields[:source_hash]
        @from = fields[:from]
        @to = fields[:to]
        @mint = fields[:mint].to_i
        @value = fields[:value].to_i
        @gas_limit = fields[:gas_limit].to_i
        @is_system_tx = fields[:is_system_tx]
        @payload = fields[:data]

        # last but not least, set the type.
        @type = TYPE_DEPOSIT
      end

      # Overloads the constructor for decoding raw transactions and creating unsigned copies.
      konstructor :decode, :unsigned_copy

      # Decodes a raw transaction hex into an {Eth::Tx::Deposit}
      # transaction object.
      #
      # @param hex [String] the raw transaction hex-string.
      # @return [Eth::Tx::Deposit] transaction payload.
      # @raise [TransactionTypeError] if transaction type is invalid.
      # @raise [ParameterError] if transaction is missing fields.
      # @raise [DecoderError] if transaction decoding fails.
      def decode(hex)
        hex = Util.remove_hex_prefix hex
        type = hex[0, 2]
        raise TransactionTypeError, "Invalid transaction type #{type}!" if type.to_i(16) != TYPE_DEPOSIT

        bin = Util.hex_to_bin hex[2..]
        tx = Rlp.decode bin

        # decoded transactions always have 7 + 2 fields, even if they are empty or zero
        raise ParameterError, "Transaction missing fields!" if tx.size < 7

        # populate the payload fields
        source_hash = Util.bin_to_hex tx[0]
        from = Util.bin_to_hex tx[1]
        to = Util.bin_to_hex tx[2]
        mint = Util.deserialize_big_endian_to_int tx[3]
        value = Util.deserialize_big_endian_to_int tx[4]
        gas_limit = Util.deserialize_big_endian_to_int tx[5]
        is_system_tx = tx[6] != "\x00"
        data = tx[7]

        # populate class attributes
        @source_hash = source_hash.to_s
        @from = from.to_s
        @to = to.to_s
        @mint = mint.to_i
        @value = value.to_i
        @gas_limit = gas_limit.to_i
        @is_system_tx = is_system_tx
        @payload = data

        # the type is deposit
        @type = TYPE_DEPOSIT
      end

      # Encodes a raw transaction object, wraps it in an EIP-2718 envelope
      # with a deposit type prefix.
      #
      # @return [String] a raw, RLP-encoded deposit type transaction object.
      def encoded
        tx_data = []
        tx_data.push Util.hex_to_bin @source_hash
        tx_data.push Util.hex_to_bin @from.to_s
        tx_data.push Util.hex_to_bin @to.to_s
        tx_data.push Util.serialize_int_to_big_endian @mint
        tx_data.push Util.serialize_int_to_big_endian @value
        tx_data.push Util.serialize_int_to_big_endian @gas_limit
        # tx_data.push @is_system_tx ? "\x01" : "\x00"
        tx_data.push @is_system_tx ? 1 : 0
        tx_data.push Rlp::Sedes.binary.serialize @payload
        tx_encoded = Rlp.encode tx_data

        # create an EIP-2718 envelope with deposit type payload
        tx_type = Util.serialize_int_to_big_endian @type
        return "#{tx_type}#{tx_encoded}"
      end

      # Gets the encoded, enveloped, raw transaction hex.
      #
      # @return [String] the raw transaction hex.
      def hex
        Util.bin_to_hex encoded
      end

      # Gets the transaction hash.
      #
      # @return [String] the transaction hash.
      def hash
        Util.bin_to_hex Util.keccak256 encoded
      end
      
      # Alias an address if it is a contract address by adding the alias mask.
      #
      # @param address [String] the original address.
      # @return [String] the aliased address if it's a contract, otherwise the original address.
      def self.alias_address(address)
        mask = 0x1111000000000000000000000000000000001111
        max_uint160 = 2**160
        aliased_address = (address.to_i(16) + mask) % max_uint160
        "0x" + aliased_address.to_s(16).rjust(40, '0')
      end
      
      # Compute the source hash based on the origin type.
      #
      # @param origin_type [Integer] the origin type (0 for user-deposited, 1 for L1 attributes, 2 for upgrade-deposited).
      # @param params [Hash] the necessary parameters for computing the source hash.
      # @return [String] the computed source hash.
      def self.compute_source_hash(origin_type, params)
        case origin_type
        when 0
          l1_block_hash = params[:l1_block_hash]
          l1_log_index = params[:l1_log_index]
          inner_hash = Digest::SHA256.digest([l1_block_hash, l1_log_index].pack("H*H*"))
          outer_hash = Digest::SHA256.hexdigest(["00", inner_hash].pack("H*H*"))
        when 1
          l1_block_hash = params[:l1_block_hash]
          seq_number = params[:seq_number]
          inner_hash = Digest::SHA256.digest([l1_block_hash, seq_number].pack("H*H*"))
          outer_hash = Digest::SHA256.hexdigest(["01", inner_hash].pack("H*H*"))
        when 2
          intent = params[:intent]
          inner_hash = Digest::SHA256.digest(intent)
          outer_hash = Digest::SHA256.hexdigest(["02", inner_hash].pack("H*H*"))
        else
          raise ArgumentError, "Invalid origin type"
        end
        outer_hash
      end
    end
  end
end
