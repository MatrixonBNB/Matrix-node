module FacetBlockImporter
  extend self
  
  def from_eth_block(eth_block)
    eth_block.reload
    
    facet_block = FacetBlock.new(
      eth_block_hash: eth_block.block_hash,
    )
    
    facet_txs = eth_block.eth_transactions.includes(:eth_calls).flat_map do |tx|
      tx.eth_calls.sort_by(&:call_index).map do |call|
        next if call.error.present?

        facet_tx = get_inner_tx(call)
      
        next unless facet_tx
        next unless facet_tx.chain_id == facet_chain_id
        
        gas_used = call.gas_used
        base_fee = tx.eth_block.base_fee_per_gas
        mint_amount = gas_used * base_fee
        
        source_hash = Eth::Util.keccak256(
          Eth::Util.int_to_big_endian(0) +
          Eth::Util.keccak256(
            tx.block_hash.hex_to_bytes +
            Eth::Util.int_to_big_endian(tx.transaction_index) +
            Eth::Util.int_to_big_endian(call.call_index)
          )
        ).bytes_to_hex
        
        computed_from = call.call_index == 0 ?
          call.from_address :
          Eth::Tx::Deposit.alias_address(call.from_address)
        
        FacetTransaction.new(
          eth_transaction_hash: tx.tx_hash,
          eth_call_index: call.call_index,
          source_hash: source_hash,
          value: facet_tx.amount,
          to_address: normalize_hex(facet_tx.destination),
          gas_limit: facet_tx.gas_limit,
          max_fee_per_gas: facet_tx.max_fee_per_gas,
          input: facet_tx.payload.bytes_to_hex,
          from_address: computed_from,
          mint: mint_amount,
        )
      end
    end.flatten.compact
    
    payload = facet_txs.map { |facet_tx| facet_tx_to_payload(facet_tx) }
    
    response = geth_driver.propose_block(payload, eth_block)

    geth_block = geth_driver.client.call("eth_getBlockByNumber", ["0x" + response['blockNumber'].to_i(16).to_s(16), true])
    update_records_from_response(response, facet_block, facet_txs, geth_block, eth_block)
  end
  
  def update_records_from_response(response, facet_block, facet_txs, geth_block, eth_block)
    ActiveRecord::Base.transaction do
      facet_block.assign_attributes(
        eth_block_hash: eth_block.block_hash,
        number: response['blockNumber'].to_i(16),
        block_hash: response['blockHash'],
        parent_hash: response['parentHash'],
        state_root: response['stateRoot'],
        receipts_root: response['receiptsRoot'],
        logs_bloom: response['logsBloom'],
        gas_limit: response['gasLimit'].to_i(16),
        gas_used: response['gasUsed'].to_i(16),
        timestamp: response['timestamp'].to_i(16),
        base_fee_per_gas: response['baseFeePerGas'].to_i(16),
        prev_randao: response['prevRandao'],
        extra_data: response['extraData'],
        parent_beacon_block_root: eth_block.parent_beacon_block_root,
        size: geth_block['size'].to_i(16),
        transactions_root: geth_block['transactionsRoot'],
      )

      facet_block.save!

      geth_block['transactions'].each do |tx|
        receipt_details = geth_driver.client.call("eth_getTransactionReceipt", [tx['hash']])

        facet_tx = facet_txs.detect { |facet_tx| facet_tx.source_hash == tx['sourceHash'] }
        binding.irb unless facet_tx

        facet_tx.update!(
          tx_hash: tx['hash'],
          block_hash: response['blockHash'],
          block_number: response['blockNumber'].to_i(16),
          transaction_index: receipt_details['transactionIndex'].to_i(16),
          deposit_receipt_version: tx['depositReceiptVersion'].to_i(16),
          gas: tx['gas'].to_i(16),
          tx_type: tx['type']
          # gas_limit: tx['gasLimit'].to_i(16),
          # gas_used: receipt_details['gasUsed'].to_i(16),
        )

        FacetTransactionReceipt.create!(
          transaction_hash: tx['hash'],
          block_hash: response['blockHash'],
          block_number: response['blockNumber'].to_i(16),
          contract_address: receipt_details['contractAddress'],
          cumulative_gas_used: receipt_details['cumulativeGasUsed'].to_i(16),
          deposit_nonce: tx['nonce'].to_i(16),
          deposit_receipt_version: tx['type'].to_i(16),
          effective_gas_price: receipt_details['effectiveGasPrice'].to_i(16),
          from_address: tx['from'],
          gas_used: receipt_details['gasUsed'].to_i(16),
          logs: receipt_details['logs'],
          logs_bloom: receipt_details['logsBloom'],
          status: receipt_details['status'].to_i(16),
          to_address: tx['to'],
          transaction_index: receipt_details['transactionIndex'].to_i(16),
          tx_type: tx['type']
        )
      end
    end
  end

  
  def geth_driver(node_url = ENV.fetch('GETH_RPC_URL', 'http://localhost:8551'))
    @_geth_driver ||= GethDriver.new(node_url)
  end
  
  def facet_tx_to_payload(facet_tx)
    Eth::Tx::Deposit.new(
      source_hash: facet_tx.source_hash,
      from: facet_tx.from_address,
      to: facet_tx.to_address,
      mint: facet_tx.mint,
      value: facet_tx.value,
      gas_limit: facet_tx.gas_limit,
      # max_fee_per_gas
      is_system_tx: false,
      data: facet_tx.input,
    ).encoded.bytes_to_hex
  end
  
  def normalize_hex(hex)
    return if hex.blank?
    (hex.start_with?("0x") ? hex : "0x#{hex}").downcase
  end
  
  def get_inner_tx(eth_call)
    Eth::Tx::Eip1559.decode(eth_call.input)
  rescue *tx_decode_errors
    nil
  end
  
  def tx_decode_errors
    [
      Eth::Rlp::DecodingError,
      Eth::Tx::TransactionTypeError,
      Eth::Tx::ParameterError,
      Eth::Tx::DecoderError
    ]
  end
  
  def facet_chain_id
    0xface7
  end
end
