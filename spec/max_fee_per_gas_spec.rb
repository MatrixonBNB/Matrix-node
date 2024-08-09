require "rails_helper"

RSpec.describe "Reverts" do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  
  let(:from_address) { "0x000000000000000000000000000000000000000a" }
  
  let!(:counter_address) {
    facet_data = EVMHelpers.get_deploy_data('contracts/Counter', [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: from_address
    )
    
    res.receipts_imported.first.contract_address
  }
  
  it "automatically uses the base fee per gas of the block" do
    res = call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'increment',
      args: [],
      max_fee_per_gas: 0
    )
    
    receipt = res.receipts_imported.first
    effective_gas_price = receipt.effective_gas_price
    
    block = FacetBlock.find_by!(number: receipt.block_number)
    base_fee_per_gas = block.calculated_base_fee_per_gas
    
    expect(effective_gas_price).to eq(base_fee_per_gas)
  end
  
  it "still fails for underpriced transactions" do
    res = call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'increment',
      args: [],
      max_fee_per_gas: 1,
      expect_failure: true
    )
  end
end
