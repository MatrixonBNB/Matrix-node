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
    
    result = client.call("eth_call", [{
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
    expect_failure: false
  )
    data = TransactionHelper.get_function_calldata(contract: contract, function: function, args: args)
    
    create_and_import_block(
      facet_data: data,
      to_address: address,
      from_address: from,
      value: value,
      gas_limit: gas_limit,
      max_fee_per_gas: max_fee_per_gas,
      expect_failure: expect_failure
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
    expect_failure: false
  )
    ActiveRecord::Base.transaction do
      EthBlockImporter.ensure_genesis_blocks
      last_block = EthBlock.order(number: :desc).first
      
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
        'hash' => "0x" + SecureRandom.hex(32),
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
          'hash' => "0x" + SecureRandom.hex(32),
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
      
      current_max_facet_block_number = FacetBlock.maximum(:number).to_i
      facet_block_number = current_max_facet_block_number + 1
      
      # Get the earliest block
      earliest = FacetBlock.order(number: :asc).first
      in_memory_blocks = FacetBlock.where(number: (current_max_facet_block_number - 64 - 1)..current_max_facet_block_number).index_by(&:number)
      head_block = in_memory_blocks[facet_block_number - 1] || earliest
      safe_block = in_memory_blocks[facet_block_number - 32] || earliest
      finalized_block = in_memory_blocks[facet_block_number - 64] || earliest
      
      eth_block = EthBlock.from_rpc_result(block_by_number_response)
      new_eth_transactions = EthTransaction.from_rpc_result(block_by_number_response['result'])
      # binding.irb
      new_eth_calls = EthCall.from_trace_result(trace_result['result'], eth_block)
      
      facet_block, facet_txs = EthBlockImporter.propose_facet_block(
        eth_block,
        eth_calls: new_eth_calls,
        eth_transactions: new_eth_transactions,
        facet_block_number: facet_block_number,
        earliest: earliest,
        head_block: head_block,
        safe_block: safe_block,
        finalized_block: finalized_block
      )
      
      if facet_txs.blank?
        raise NoValidFacetTransactions
      end
      
      facet_block, facet_txs, facet_receipts = EthBlockImporter.fill_in_block_data(facet_block, facet_txs)

      res = OpenStruct.new
      res.receipts_imported = facet_receipts
      res.transactions_imported = facet_txs
      
      if facet_receipts.map(&:status) != [1] && facet_receipts.present?
        ap facet_txs.first
        ap facet_receipts.first
        ap facet_receipts.first.trace
      end
      
      expected = expect_failure ? [0] : [1]
      
      eth_block.save!
      facet_block.save!
      FacetTransaction.import!(facet_txs)
      FacetTransactionReceipt.import!(facet_receipts)
      
      expect(facet_receipts.map(&:status).uniq).to eq(expected)
      res
    end
  end
  
  def trigger_contract_interaction(from:, payload:, expect_failure: false, block_timestamp: nil)
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
        args: payload[:data][:args].values,
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