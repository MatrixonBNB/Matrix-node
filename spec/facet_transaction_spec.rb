# spec/models/facet_transaction_spec.rb
require 'rails_helper'

RSpec.describe FacetTransaction do
  describe '.deserialize_rlp_int' do
    context 'with valid RLP integers' do
      it 'deserializes empty string to zero' do
        expect(FacetTransaction.deserialize_rlp_int(''.b)).to eq(0)
      end

      it 'deserializes valid non-zero integers' do
        expect(FacetTransaction.deserialize_rlp_int("\x01".b)).to eq(1)
        expect(FacetTransaction.deserialize_rlp_int("\xff".b)).to eq(255)
        expect(FacetTransaction.deserialize_rlp_int("\x0f".b)).to eq(15)
      end

      it 'handles large numbers' do
        expect(FacetTransaction.deserialize_rlp_int("\xff\xff\xff\xff".b)).to eq(4294967295)
      end
    end

    context 'with invalid RLP integers' do
      it 'rejects integers with leading zeros' do
        expect {
          FacetTransaction.deserialize_rlp_int("\x00".b)
        }.to raise_error(FacetTransaction::InvalidRlpInt)

        expect {
          FacetTransaction.deserialize_rlp_int("\x00\x01".b)
        }.to raise_error(FacetTransaction::InvalidRlpInt)
      end
    end
  end

  describe '.from_payload' do
    let(:contract_initiated) { false }
    let(:from_address) { "0x" + "2" * 40 }
    let(:tx_hash) { "0x" + "3" * 64 }
    let(:block_hash) { "0x" + "4" * 64 }
    
    def encode_tx(params)
      # Default valid parameters
      defaults = {
        chain_id: ChainIdManager.current_l2_chain_id,
        to: "0x" + "5" * 40,
        value: 1000,
        max_gas_fee: 1_000_000,
        gas_limit: 1_000_000,
        data: "0x"
      }
      
      params = defaults.merge(params)
      
      # RLP encode the transaction
      rlp_encoded = Eth::Rlp.encode([
        Eth::Util.serialize_int_to_big_endian(params[:chain_id]),
        Eth::Util.hex_to_bin(params[:to]),
        Eth::Util.serialize_int_to_big_endian(params[:value]),
        Eth::Util.serialize_int_to_big_endian(params[:max_gas_fee]),
        Eth::Util.serialize_int_to_big_endian(params[:gas_limit]),
        Eth::Util.hex_to_bin(params[:data])
      ])
      
      # Add transaction type prefix
      "0x#{FacetTransaction::FACET_TX_TYPE.to_s(16).rjust(2, '0')}#{rlp_encoded.bytes_to_hex}"
    end

    context 'with valid transaction' do
      it 'decodes a basic transaction' do
        input = encode_tx({})
        
        tx = FacetTransaction.from_payload(
          contract_initiated: contract_initiated,
          from_address: from_address,
          input: input,
          tx_hash: tx_hash,
          block_hash: block_hash
        )
        
        expect(tx).to be_a(FacetTransaction)
        expect(tx.chain_id).to eq(ChainIdManager.current_l2_chain_id)
        expect(tx.from_address).to eq(from_address)
        expect(tx.contract_initiated).to eq(contract_initiated)
        expect(tx.eth_transaction_hash).to eq(tx_hash)
      end
    end

    context 'with invalid transaction' do
      it 'returns nil for invalid transaction type' do
        input = "0x00" + encode_tx({}).slice(4..)
        
        tx = FacetTransaction.from_payload(
          contract_initiated: contract_initiated,
          from_address: from_address,
          input: input,
          tx_hash: tx_hash,
          block_hash: block_hash
        )
        
        expect(tx).to be_nil
      end

      it 'returns nil for invalid RLP integers' do
        # Create transaction with leading zeros in value
        input = encode_tx({})
        modified_input = input.sub(/0x46[0-9a-f]*/) { |match|
          # Insert leading zero in the value field
          "\x46" + Eth::Rlp.encode([
            Eth::Util.serialize_int_to_big_endian(ChainIdManager.current_l2_chain_id),
            Eth::Util.hex_to_bin("0x" + "5" * 40),
            "\x00\x01",  # Value with leading zero
            Eth::Util.serialize_int_to_big_endian(1_000_000),
            Eth::Util.serialize_int_to_big_endian(1_000_000),
            ""
          ]).bytes_to_hex
        }
        
        tx = FacetTransaction.from_payload(
          contract_initiated: contract_initiated,
          from_address: from_address,
          input: modified_input,
          tx_hash: tx_hash,
          block_hash: block_hash
        )
        
        expect(tx).to be_nil
      end
    end
  end
end
