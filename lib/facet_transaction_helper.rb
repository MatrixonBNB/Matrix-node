module FacetTransactionHelper
  def import_eth_tx(
    from_address: "0x" + "2" * 40,
    input:,
    events: [],
    expect_error: false,
    expect_no_tx: false
  )
    from_address = from_address.downcase
    mock_ethereum_client = instance_double(EthRpcClient)
    
    current_max_eth_block = EthBlockImporter.instance.current_max_eth_block
    
    eth_transaction = EthTransaction.new(
      block_hash: bytes_stub(rand),
      block_number: current_max_eth_block.number + 1,
      block_timestamp: current_max_eth_block.timestamp + 12,
      tx_hash: bytes_stub(rand),
      transaction_index: 0,
      input: input,
      chain_id: 1,
      from_address: from_address,
      to_address: FacetTransaction::FACET_INBOX_ADDRESS,
      status: 1,
      logs: events
    )
 
    rpc_results = EthTransaction.to_rpc_result([eth_transaction])
    block_result = rpc_results[0].merge('parentHash' => current_max_eth_block.block_hash)
    receipt_result = rpc_results[1]
    
    instance = EthBlockImporter.instance
    
    instance.ethereum_client = mock_ethereum_client

    allow(mock_ethereum_client).to receive(:get_block_number).and_return(eth_transaction.block_number)
    allow(mock_ethereum_client).to receive(:get_block).and_return(block_result)
    allow(mock_ethereum_client).to receive(:get_transaction_receipts).and_return(receipt_result)

    allow_any_instance_of(SysConfig).to receive(:block_in_v2?).and_return(true)
    
    importer = EthBlockImporter.instance
    facet_blocks, eth_blocks = importer.import_next_block
    
    latest_l2_block = EthRpcClient.l2.get_block("latest", true)
    
    tx_in_geth = latest_l2_block['transactions'].find do |tx|
      tx['sourceHash'] == eth_transaction.facet_tx_source_hash
    end
    
    if expect_no_tx
      expect(tx_in_geth).to be_nil
      return
    end
    
    expect(tx_in_geth).to be_present
    
    receipt_in_geth = EthRpcClient.l2.get_transaction_receipt(tx_in_geth['hash'])
    
    expect(receipt_in_geth).to be_present
    
    combined_receipt = combine_transaction_data(receipt_in_geth, tx_in_geth)
    combined_receipt.l2_block = latest_l2_block
    
    expected_status = expect_error ? 0 : 1
    unless combined_receipt.status == expected_status
      ap EthRpcClient.l2.trace(combined_receipt.hash)
      binding.irb
    end
    expect(combined_receipt.status).to eq(expected_status)
    expect(combined_receipt.l1TxOrigin).to eq(eth_transaction.from_address)
    
    combined_receipt
  end

  def alias_addr(addr)
    AddressAliasHelper.apply_l1_to_l2_alias(addr)
  end
  
  def bytes_stub(i, len = 32)
    hsh = Eth::Util.keccak256(["stub", i.to_s].join(":"))
    hsh.last(len).bytes_to_hex
  end

  def generate_facet_tx_payload(
    input:,
    to:,
    gas_limit:,
    max_fee_per_gas: 10.gwei,
    value: 0
  )
    chain_id = ChainIdManager.current_l2_chain_id
    
    rlp_encoded = Eth::Rlp.encode([
      Eth::Util.serialize_int_to_big_endian(chain_id),
      Eth::Util.hex_to_bin(to.to_s),
      Eth::Util.serialize_int_to_big_endian(value),
      Eth::Util.serialize_int_to_big_endian(max_fee_per_gas),
      Eth::Util.serialize_int_to_big_endian(gas_limit),
      Eth::Util.hex_to_bin(input)
    ])

    "0x#{FacetTransaction::FACET_TX_TYPE.to_s(16).rjust(2, '0')}#{rlp_encoded.unpack1('H*')}"
  end
  
  def calldata_mint_amount(hex_string)
    bytes = hex_string.hex_to_bytes
    zero_count = bytes.count("\x00")
    non_zero_count = bytes.bytesize - zero_count
    
    zero_count * 4 + non_zero_count * 16
  end
  
  def generate_event_log(data, from_address, log_index, removed = false)
    {
      'address' => from_address,
      'topics' => [EthTransaction::FacetLogInboxEventSig],
      'data' => data,
      'logIndex' => "0x" + log_index.to_s(16),
      'removed' => removed
    }
  end
  
  def calldata_mint_amount_for_tx(hex_string)
    halving_periods_passed = 0
    calldata_mint_amount(hex_string) * SysConfig::INITIAL_FCT_MINT_PER_L1_GAS / (2 ** halving_periods_passed)
  end
  
  def expect_calldata_mint_to_be(hex_string, expected_mint)
    expect(calldata_mint_amount_for_tx(hex_string)).to eq(expected_mint)
  end

  def combine_transaction_data(receipt, tx_data)
    combined = receipt.merge(tx_data) do |key, receipt_val, tx_val|
      if receipt_val != tx_val
        [receipt_val, tx_val]
      else
        receipt_val
      end
    end
  
    # Convert hex strings to integers where appropriate
    %w[blockNumber gasUsed cumulativeGasUsed effectiveGasPrice status transactionIndex nonce value gas depositNonce mint depositReceiptVersion gasPrice].each do |key|
      combined[key] = combined[key].to_i(16) if combined[key].is_a?(String) && combined[key].start_with?('0x')
    end
  
    # Remove duplicate keys with different casing
    combined.delete('transactionHash')  # Keep 'transactionHash' instead
  
    obj = OpenStruct.new(combined)
    
    def obj.method_missing(method, *args, &block)
      if respond_to?(method.to_s.camelize(:lower))
        send(method.to_s.camelize(:lower), *args, &block)
      else
        super
      end
    end
    
    def obj.decoded_logs
      FacetTransactionReceipt.new(logs: self.logs).decoded_logs
    end
    
    obj
  end
end
