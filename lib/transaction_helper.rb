module TransactionHelper
  include EVMHelpers
  extend self
  
  @contract_addresses = {}
  
  class << self
    attr_accessor :contract_addresses
  end
  
  def client
    GethDriver.client
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
  
  def get_function_calldata(
    contract:,
    function:,
    args:
  )
    contract_object = get_contract(contract, "0x0000000000000000000000000000000000000000")
    
    function_obj = contract_object.parent.function_hash[function]
    function_obj.get_call_data(*args)
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
    data = get_function_calldata(contract: contract, function: function, args: args)
    
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
    data = get_deploy_data(contract, args)
    
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
    implementation_address = deploy_contract(
      from: from,
      contract: implementation,
      args: [],
      value: value,
      gas_limit: gas_limit,
      max_fee_per_gas: max_fee_per_gas,
      expect_failure: expect_failure
    ).contract_address
    
    initialize_calldata = get_function_calldata(
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
    chain_id: FacetTransaction::FACET_CHAIN_ID,
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
    
      trace_response = {
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
    
      res = EthBlockImporter.import_block(block_by_number_response, trace_response)
      
      unless res.receipts_imported.map(&:status) == [1]
        trace = GethDriver.non_auth_client.call("debug_traceTransaction", [res.receipts_imported.last.transaction_hash, {
          enableMemory: true,
          disableStack: false,
          disableStorage: false,
          enableReturnData: true,
          debug: true,
          tracer: "callTracer"
        }])
        
        trace = GethDriver.non_auth_client.call("debug_traceBlockByNumber", ["0x" + res.receipts_imported.last.block_number.to_s(16), {
          enableMemory: true,
          disableStack: false,
          disableStorage: false,
          enableReturnData: true,
          debug: true,
          tracer: "callTracer"
        }])
        
        trace.each do |call|
          if call['result']['calls']
            call['result']['calls'].each do |sub_call|
              if sub_call['to'] == '0x000000000000000000636f6e736f6c652e6c6f67'
                data = sub_call['input'][10..-1]
                
                decoded_data = Eth::Abi.decode(['string'], [data].pack('H*')) rescue [data]
                
                decoded_log = decoded_data.first
                sub_call['console.log'] = decoded_log
                sub_call.delete('input')
                sub_call.delete('gas')
                sub_call.delete('gasUsed')
                sub_call.delete('to')
                sub_call.delete('type')
              end
            end
          end
        end
        
        # ap trace
      end
      
      expected = expect_failure ? [0] : [1]
      
      expect(res.receipts_imported.map(&:status).uniq).to eq(expected)
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
    res = trigger_contract_interaction(from: from, payload: payload, expect_failure: false, block_timestamp: block_timestamp)

    # Ensure the transaction was successful
    unless res.receipts_imported.map(&:status).uniq == [1]
      raise "Transaction failed"
    end

    res
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