require "rails_helper"

RSpec.describe "Reverts" do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  
  let(:from_address) { "0x000000000000000000000000000000000000000a" }
  
  let(:counter_contract) { EVMHelpers.compile_contract('contracts/Counter') }
  
  let!(:counter_address) {
    facet_data = EVMHelpers.get_deploy_data(counter_contract, [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: from_address
    )
    
    res.contract_address
  }
  
  it "automatically uses the base fee per gas of the block" do
    res = call_contract_function(
      contract: counter_contract,
      address: counter_address,
      from: from_address,
      function: 'increment',
      args: [],
      max_fee_per_gas: 0
    )
    
    receipt = res
    effective_gas_price = receipt.effective_gas_price
    
    block = GethDriver.non_auth_client.call('eth_getBlockByNumber', ["0x" + receipt.block_number.to_s(16), true])
    
    block = FacetBlock.from_rpc_result(block)
    base_fee_per_gas = block.calculated_base_fee_per_gas
    
    expect(effective_gas_price).to eq(base_fee_per_gas)
  end
  
  it "still fails for underpriced transactions" do
    res = call_contract_function(
      contract: counter_contract,
      address: counter_address,
      from: from_address,
      function: 'increment',
      args: [],
      max_fee_per_gas: 1,
      expect_failure: true
    )
  end
end
