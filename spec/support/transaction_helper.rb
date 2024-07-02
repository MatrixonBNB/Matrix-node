module TransactionHelper
  include EvmHelpers
  
  def static_call(contract:, address:, function:, args:)
    contract_object = get_contract(contract, address)
    
    function_obj = contract_object.parent.function_hash[function]
    data = function_obj.get_call_data(*args)
    
    result = client.call("eth_call", [{
      to: address,
      data: data
    }, "latest"])
    
    function_obj.parse_result(result)
  end
  
  def call_contract_function(
    contract:,
    address:,
    from:,
    function:,
    args:,
    value: 0,
    gas_limit: 1_000_000
  )
    contract_object = get_contract(contract, address)
    
    function_obj = contract_object.parent.function_hash[function]
    data = function_obj.get_call_data(*args)
    
    create_and_import_block(
      facet_data: data,
      to_address: address,
      from_address: from,
      value: value,
      gas_limit: gas_limit
    )
  end
  
  def create_and_import_block(
    facet_data:,
    from_address:,
    to_address:,
    value: 0,
    max_fee_per_gas: 10.gwei,
    gas_limit: 1_000_000,
    eth_base_fee: 200.gwei,
    eth_gas_used: 1e18.to_i,
    chain_id: 0xface7
  )
    ActiveRecord::Base.transaction do
      EthBlockImporter.ensure_genesis_blocks
      last_block = EthBlock.order(number: :desc).first
      
      eth_data = FacetTransaction.new(
        chain_id: chain_id,
        to_address: to_address,
        from_address: from_address,
        value: value,
        max_fee_per_gas: max_fee_per_gas,
        gas_limit: gas_limit.to_i,
        input: facet_data
      ).to_eth_payload
    
      transaction = {
        'hash' => "0x" + SecureRandom.hex(32),
        'from' => from_address,
        'to' => to_address,
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
          'transactions' => [transaction],
          'baseFeePerGas' => '0x' + eth_base_fee.to_s(16),
          'gasUsed' => '0xf4240',
          'timestamp' => (last_block.timestamp + 12).to_s(16),
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
            'txHash' => transaction['hash'],
            'result' => {
              'from' => transaction['from'],
              'to' => transaction['to'],
              'gasUsed' => "0x" + eth_gas_used.to_s(16),
              'gas' => transaction['gas'],
              'output' => '0x',
              'input' => transaction['input']
            }
          }
        ]
      }
    
      res = EthBlockImporter.import_block(block_by_number_response, trace_response)
      
      unless res.receipts_imported.map(&:status) == [1]
        trace = GethClient.new('http://localhost:8545').call("debug_traceTransaction", [res.receipts_imported.last.transaction_hash, {
          enableMemory: true,
          disableStack: false,
          disableStorage: false,
          enableReturnData: true,
          debug: true,
          tracer: "callTracer"
        }])
        
        trace = GethClient.new('http://localhost:8545').call("debug_traceBlockByNumber", ["0x" + res.receipts_imported.last.block_number.to_s(16), {
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
        
        ap trace
      end
      
      expect(res.receipts_imported.map(&:status)).to eq([1])
      res
    end
  end
end