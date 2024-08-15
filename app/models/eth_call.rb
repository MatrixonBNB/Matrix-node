class EthCall < ApplicationRecord
  validates :block_hash, :transaction_hash, :from_address, :gas, :gas_used, presence: true
  
  belongs_to :eth_block, foreign_key: :block_hash, primary_key: :block_hash
  belongs_to :eth_transaction, foreign_key: :transaction_hash, primary_key: :tx_hash
  
  before_validation :remove_null_bytes
  
  def remove_null_bytes
    self.revert_reason = revert_reason.delete("\u0000") if revert_reason
  end
  
  def self.from_trace_result(trace_result, eth_block)
    order_counter = Struct.new(:count).new(0)
    
    trace_result.each_with_object([]) do |trace, traces|
      traces.concat(process_trace(trace, eth_block, order_counter))
    end
  end

  private

  def self.process_trace(trace, eth_block, order_counter, parent_traced_call = nil)
    result = trace['result']
    current_order = order_counter.count
    order_counter.count += 1

    traces = []
    # Check if the current call is relevant
    if result['to'] == FacetTransaction::FACET_INBOX_ADDRESS && result['error'].nil?
      traced_call = EthCall.new(
        block_hash: eth_block.block_hash,
        block_number: eth_block.number,
        transaction_hash: trace['txHash'],
        from_address: result['from'],
        to_address: result['to'],
        gas: result['gas'].to_i(16),
        gas_used: result['gasUsed'].to_i(16),
        input: result['input'],
        output: result['output'],
        value: result['value'],
        call_type: result['type'],
        error: result['error'],
        revert_reason: result['revertReason'],
        call_index: current_order,
        parent_call_index: parent_traced_call&.call_index
      )
      
      traces << traced_call
    end
  
    # Always process sub-calls
    if result['calls']
      result['calls'].each do |sub_call|
        traces.concat(process_trace(
          { 'txHash' => trace['txHash'], 'result' => sub_call },
          eth_block,
          order_counter,
          traced_call
        ))
      end
    end
    
    traces
  end
end
