module TransactionHelper
  include EVMHelpers
  include Memery
  class << self
    include Memery
    include EVMHelpers
  end
  extend self
  
  class NoValidFacetTransactions < StandardError; end
  
  @contract_addresses = {}
  
  class << self
    attr_accessor :contract_addresses
  end
  
  def client
    GethDriver.client
  end
  
  def calculate_next_base_fee(prev_block_number)
    prev_block = get_block(prev_block_number)
    prev_block_gas_used = prev_block['gasUsed'].to_i(16)
    prev_block_gas_limit = prev_block['gasLimit'].to_i(16)
    prev_block_base_fee = prev_block['baseFeePerGas'].to_i(16)
  
    elasticity_multiplier = 2
    base_fee_change_denominator = 8
  
    parent_gas_target = prev_block_gas_limit / elasticity_multiplier
  
    if prev_block_gas_used == parent_gas_target
      return prev_block_base_fee
    end
  
    num = 0
    denom = parent_gas_target * base_fee_change_denominator
  
    if prev_block_gas_used > parent_gas_target
      num = prev_block_base_fee * (prev_block_gas_used - parent_gas_target)
      base_fee_delta = [num / denom, 1].max
      next_base_fee = prev_block_base_fee + base_fee_delta
    else
      num = prev_block_base_fee * (parent_gas_target - prev_block_gas_used)
      base_fee_delta = num / denom
      next_base_fee = [prev_block_base_fee - base_fee_delta, 0].max
    end
  
    next_base_fee
  end
  
  def get_block(number, get_transactions = false)
    if number.is_a?(String)
      return client.call("eth_getBlockByNumber", [number, get_transactions])
    end
    
    client.call("eth_getBlockByNumber", ["0x" + number.to_s(16), get_transactions])
  end
  
  def balance(address)
    client.call("eth_getBalance", [address, "latest"]).to_i(16)
  end
  
  def call(payload)
    client.call("eth_call", [payload, "latest"])
  end
  
  def code_at_address(address)
    client.call("eth_getCode", [address, "latest"])
  end
  
  def get_feth_balance(address = "0xC2172a6315c1D7f6855768F843c420EbB36eDa97".downcase)
    feth_address = '0x1673540243e793b0e77c038d4a88448eff524dce'
    function = 'balanceOf'
    args = [address]
    contract = "legacy/FacetERC20"
    
    static_call(contract: contract, address: feth_address, function: function, args: args)
  end
  
  def static_call(contract:, address:, function:, args:)
    contract_object = get_contract(contract, address)
    
    function_obj = contract_object.parent.function_hash[function]
    data = function_obj.get_call_data(*args) rescue binding.irb
    
    # GethDriver.non_auth_client.call("debug_traceCall", [{
    #   to: address,
    #   data: data
    # }, "latest", {
    #   tracer: "callTracer"
    # }])
    
    result = GethDriver.non_auth_client.call("eth_call", [{
      to: address,
      data: data
    }, "latest"])
    
    function_obj.parse_result(result)
  end
  
  class << self
    def get_function_calldata(
      contract:,
      function:,
      args:
    )
      contract_object = compile_contract(contract)
      
      function_obj = contract_object.parent.function_hash[function]
      function_obj.get_call_data(*args).freeze
    end
    memoize :get_function_calldata
  end
  
  def call_contract_function(
    contract:,
    address:,
    from:,
    function:,
    args:,
    value: 0,
    gas_limit: 10_000_000,
    max_fee_per_gas: 10.gwei,
    expect_failure: false,
    expect_blank: false
  )
    data = TransactionHelper.get_function_calldata(contract: contract, function: function, args: args)
    
    create_and_import_block(
      facet_data: data,
      to_address: address,
      from_address: from,
      value: value,
      gas_limit: gas_limit,
      max_fee_per_gas: max_fee_per_gas,
      expect_failure: expect_failure,
      expect_blank: expect_blank
    )
  end
  
  def deploy_contract(
    from:,
    contract:,
    args: [],
    value: 0,
    gas_limit: 10_000_000,
    max_fee_per_gas: 10.gwei,
    expect_failure: false
  )
    data = EVMHelpers.get_deploy_data(contract, args)
    
    res = create_and_import_block(
      facet_data: data,
      to_address: nil,
      from_address: from,
      value: value,
      gas_limit: gas_limit,
      max_fee_per_gas: max_fee_per_gas,
      expect_failure: expect_failure
    ).receipts_imported.first
    
    TransactionHelper.contract_addresses[res.contract_address] = contract
    res
  end
  
  def deploy_contract_with_proxy(
    from:,
    implementation:,
    args: [],
    value: 0,
    gas_limit: 10_000_000,
    max_fee_per_gas: 10.gwei,
    expect_failure: false
  )
    pre_deploy = Ethscription.predeploy_to_local_map.invert[implementation.split("/").last]
    
    implementation_address = if pre_deploy
      pre_deploy
    else
      deploy_contract(
        from: from,
        contract: implementation,
        args: [],
        value: value,
        gas_limit: gas_limit,
        max_fee_per_gas: max_fee_per_gas,
        expect_failure: expect_failure
      ).contract_address  
    end
  
    initialize_calldata = TransactionHelper.get_function_calldata(
      contract: implementation,
      function: 'initialize',
      args: args
    )
    
    res = deploy_contract(
      from: from,
      contract: 'legacy/ERC1967Proxy',
      args: [implementation_address, initialize_calldata],
      value: value,
      gas_limit: gas_limit,
      max_fee_per_gas: max_fee_per_gas,
      expect_failure: expect_failure
    )
    
    TransactionHelper.contract_addresses[res.contract_address] = implementation
    res
  end
  
  def create_and_import_block(
    facet_data:,
    from_address:,
    to_address:,
    value: 0,
    block_timestamp: nil,
    max_fee_per_gas: 10.gwei,
    gas_limit: 10_000_000,
    eth_base_fee: 200.gwei,
    eth_gas_used: 1e18.to_i,
    chain_id: FacetTransaction.current_chain_id,
    expect_failure: false,
    expect_blank: false
  )
    last_block = EthBlockImporter.instance.current_max_eth_block
        
    if block_timestamp && block_timestamp.is_a?(Time)
      block_timestamp = block_timestamp.to_i
    end
    
    eth_data = FacetTransaction.new(
      chain_id: chain_id,
      to_address: to_address,
      from_address: from_address,
      value: value,
      max_fee_per_gas: max_fee_per_gas,
      gas_limit: gas_limit.to_i,
      input: facet_data
    ).to_eth_payload

    eth_transaction = {
      'hash' => (last_block.number + 3999).zpad(32).bytes_to_hex,
      'from' => from_address,
      'to' => "0x1111000000000000000000000000000000002222",
      'gas' => '0xf4240', # Gas limit in hex (1,000,000 in decimal)
      'gasPrice' => '0x3b9aca00', # Gas price in hex
      'input' => eth_data,
      'nonce' => '0x0',
      'value' => '0x0',
      'maxFeePerGas' => "0x123456",
      'maxPriorityFeePerGas' => '0x3b9aca00',
      'transactionIndex' => '0x0',
      'type' => '0x2',
      'chainId' => '0x1',
      'v' => '0x1b',
      'r' => '0x' + SecureRandom.hex(32),
      's' => '0x' + SecureRandom.hex(32),
      'yParity' => '0x0',
      'accessList' => []
    }

    block_by_number_response = {
      'result' => {
        'number' => (last_block.number + 1).to_s(16),
        'hash' => (last_block.number + 9999).zpad(32).bytes_to_hex,
        'parentHash' => last_block.block_hash,
        'transactions' => [eth_transaction],
        'baseFeePerGas' => '0x' + eth_base_fee.to_s(16),
        'gasUsed' => '0xf4240',
        'timestamp' => (block_timestamp || last_block.timestamp + 12).to_s(16),
        'excessBlobGas' => "0x0",
        'blobGasUsed' => "0x0",
        'difficulty' => "0x0",
        'gasLimit' => "0x0",
        'parentBeaconBlockRoot' => "0x" + SecureRandom.hex(32),
        'size' => "0x0",
        'logsBloom' => "0x0",
        'receiptsRoot' => "0x" + SecureRandom.hex(32),
        'stateRoot' => "0x" + SecureRandom.hex(32),
        'extraData' => "0x" + SecureRandom.hex(32),
        'transactionsRoot' => "0x" + SecureRandom.hex(32),
        'mixHash' => "0x" + SecureRandom.hex(32),
        'withdrawalsRoot' => "0x" + SecureRandom.hex(32),
        'miner' => "0x" + SecureRandom.hex(20),
        'nonce' => "0x0",
        'totalDifficulty' => "0x0",
      }
    }

    trace_result = {
      'result' => [
        {
          'txHash' => eth_transaction['hash'],
          'result' => {
            'from' => eth_transaction['from'],
            'to' => FacetTransaction::FACET_INBOX_ADDRESS,
            'gasUsed' => "0x" + eth_gas_used.to_s(16),
            'gas' => eth_transaction['gas'],
            'output' => '0x',
            'input' => eth_transaction['input']
          }
        }
      ]
    }
    
    receipts_result = {
      'result' => [
        {
          'transactionHash' => eth_transaction['hash'],
          'status' => 1
        }
      ]
    }
    
    dummy_client = Object.new
    
    dummy_client.define_singleton_method(:get_block) do |block_number, get_txs = false|
      block_by_number_response
    end

    dummy_client.define_singleton_method(:debug_trace_block_by_number) do |block_number|
      trace_result
    end

    dummy_client.define_singleton_method(:get_transaction_receipts) do |block_number, blocks_behind: 1000|
      nil
    end

    dummy_client.define_singleton_method(:get_block_number) do
      last_block.number + 3999
    end
    
    EthBlockImporter.instance.define_singleton_method(:blocks_behind) do
      1
    end
    
    old_client = EthBlockImporter.instance.ethereum_client
    EthBlockImporter.instance.ethereum_client = dummy_client
    
    facet_blocks, eth_blocks = EthBlockImporter.instance.import_next_block
    facet_block, eth_block = facet_blocks.first, eth_blocks.first
    
    facet_block, facet_txs, facet_receipts = fill_in_block_data(facet_block)
    facet_txs = facet_txs.reject{|tx| tx.from_address == "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001" }
    facet_receipts = facet_receipts.reject{|tx| tx.from_address == "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0001" }
    
    res = OpenStruct.new
    res.receipts_imported = facet_receipts
    res.transactions_imported = facet_txs
    
    if facet_receipts.map(&:status) != [1] && facet_receipts.present?
      ap facet_txs.first
      ap facet_receipts.first
      ap facet_receipts.first.trace
    end
    
    expected = expect_failure ? [0] : [1]
    expected = expect_blank ? [] : expected
    
    expect(facet_receipts.map(&:status).uniq).to eq(expected)
    res
  ensure
    EthBlockImporter.instance.ethereum_client = old_client
  end
  
  def fill_in_block_data(facet_block)
    geth_block = GethDriver.client.call("eth_getBlockByNumber", ["0x" + facet_block.number.to_s(16), true])
    receipts_data = GethDriver.client.call("eth_getBlockReceipts", ["0x" + facet_block.number.to_s(16)])
    
    facet_block.from_rpc_response(geth_block)

    receipts_data_by_hash = receipts_data.index_by { |receipt| receipt['transactionHash'] }

    receipts = []
    facet_txs = []

    geth_block['transactions'].each.with_index do |tx, index|
      receipt_details = receipts_data_by_hash[tx['hash']]

      facet_tx = FacetTransaction.new(source_hash: tx['sourceHash'])

      facet_tx.assign_attributes(
        tx_hash: tx['hash'],
        transaction_index: receipt_details['transactionIndex'].to_i(16),
        deposit_receipt_version: tx['depositReceiptVersion'].to_i(16),
        gas: tx['gas'].to_i(16),
        tx_type: tx['type'],
        from_address: tx['from'],
        to_address: tx['to'],
        value: tx['value'].to_i(16),
        input: tx['input'],
        mint: tx['mint'].to_i(16)
      )

      facet_receipt = FacetTransactionReceipt.new(
        transaction_hash: tx['hash'],
        block_hash: facet_block.block_hash,
        block_number: facet_block.number,
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
      
      facet_txs << facet_tx
      receipts << facet_receipt
    end

    [facet_block, facet_txs, receipts]
  end
  
  def trigger_contract_interaction(from:, payload:, expect_failure: false, expect_blank: false, block_timestamp: nil)
    contract = TransactionHelper.contract_addresses.fetch(payload[:to]) rescue binding.irb

    contract = get_contract(contract, payload[:to])
    function = contract.functions.find { |f| f.name == payload[:data][:function] }
    args = convert_args(contract, payload[:data][:function], payload[:data][:args])

    # Get the call data for the function
    call_data = function.get_call_data(*args) rescue binding.irb

    # Create and import the block
    res = create_and_import_block(
      facet_data: call_data,
      from_address: from,
      to_address: payload[:to],
      value: payload[:data][:value] || 0,
      max_fee_per_gas: payload[:data][:max_fee_per_gas] || 10.gwei,
      gas_limit: payload[:data][:gas_limit] || 10_000_000,
      expect_failure: expect_failure,
      block_timestamp: block_timestamp
    )

    res
  rescue => e
    binding.pry
    raise
  end

  def trigger_contract_interaction_and_expect_success(from:, payload:, block_timestamp: nil)
    if payload[:to].nil?
      res = deploy_contract_with_proxy(
        from: from,
        implementation: payload[:data][:type],
        args: (payload[:data][:args].is_a?(Hash) ? payload[:data][:args].values : payload[:data][:args]),
        value: payload[:data][:value] || 0,
        gas_limit: payload[:data][:gas_limit] || 10_000_000,
        max_fee_per_gas: payload[:data][:max_fee_per_gas] || 10.gwei,
        expect_failure: false
      )
    else
      res = trigger_contract_interaction(from: from, payload: payload, expect_failure: false, block_timestamp: block_timestamp)
      
      unless res.receipts_imported.map(&:status) == [1]
        raise "Transaction failed"
      end
      
      res.receipts_imported.first
    end
  end

  def trigger_contract_interaction_and_expect_error(from:, payload:, error_msg_includes: nil, block_timestamp: nil)
    res = trigger_contract_interaction(from: from, payload: payload, expect_failure: true, block_timestamp: block_timestamp)

    # Ensure the transaction failed
    if res.receipts_imported.map(&:status).uniq == [1]
      raise "Transaction succeeded unexpectedly"
    end

    # Check for the expected error message
    # unless res.error_message.include?(error_msg_includes)
    #   raise "Expected error message not found"
    # end

    res
  end
  
  def convert_args(contract, function_name, args)
    function = contract.functions.find { |f| f.name == function_name }
    inputs = function.inputs

    # If args is a string, treat it as a one-element array
    args = [args] if args.is_a?(String) || args.is_a?(Integer)

    # If args is a hash, convert it to an array based on the function inputs
    if args.is_a?(Hash)
      args_hash = args.with_indifferent_access
      args = inputs.map do |input|
        args_hash[input.name]
      end
    end

    # Ensure proper type conversion for uint and int types
    args = args&.each_with_index&.map do |arg_value, index|
      input = inputs[index]
      if arg_value.is_a?(String) && (input.type.starts_with?('uint') || input.type.starts_with?('int'))
        arg_value = Integer(arg_value, 10)
      end
      arg_value
    end

    args
  rescue => e
    binding.irb
    raise
  end
  
  def make_static_call(contract:, function_name:, function_args: {})
    address = contract
    contract = TransactionHelper.contract_addresses.fetch(contract) rescue binding.irb

    contract_object = get_contract(contract, address)
    args = convert_args(contract_object, function_name, function_args)
    res = static_call(contract: contract, address: address, function: function_name, args: args)
    
    return unless res
    
    # if res.length == 1
    #   res.is_a?(Hash) ? res.values.first : res.first
    # else
      res
    # end
  end
end