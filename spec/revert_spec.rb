require "rails_helper"

RSpec.describe "Reverts" do
  let(:node_url) { 'http://localhost:8551' }
  let(:client) { GethClient.new(node_url) }
  let(:engine_api) { GethDriver }
  
  let(:from_address) { "0x000000000000000000000000000000000000000a" }
  
  let!(:counter_address) {
    facet_data = get_deploy_data('contracts/Counter', [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: from_address
    )
    
    res.receipts_imported.first.contract_address
  }
  
  it 'handles reverts' do
    call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'createRevert',
      args: [false]
    )
    
    call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'createRevert',
      args: [true],
      expect_failure: true
    )
  end
  
  it 'calls to non-existant function' do
    create_and_import_block(
      facet_data: "0x1234",
      to_address: counter_address,
      from_address: from_address,
      expect_failure: true
    )
  end
  
  it 'deploys an invalid contract' do
    create_and_import_block(
      facet_data: "0x1234",
      to_address: nil,
      from_address: from_address,
      expect_failure: true
    )
  end
  
  it 'calls with wrong args' do
    data = get_function_calldata(contract: 'contracts/Counter', function: 'createRevert', args: [false])
    data[-1] = 'a'
    
    create_and_import_block(
      facet_data: data,
      to_address: counter_address,
      from_address: from_address,
      expect_failure: true
    )
  end
  
  it 'runs out of gas' do
    call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'runOutOfGas',
      args: [],
      expect_failure: true
    )
  end
  
  it 'sets an invalid to' do
    expect {
      create_and_import_block(
        facet_data: "0x",
        to_address: "0x1234",
        from_address: from_address,
        expect_failure: true
      )
    }.to raise_error(FacetTransaction::InvalidAddress)
  end
  
  it 'is underpriced' do
    call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'createRevert',
      args: [false],
      max_fee_per_gas: 100.gwei,
    )
    
    call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'createRevert',
      args: [false],
      max_fee_per_gas: 0,
      expect_failure: true
    )
  end
  
  it 'tries to transfer too much' do
    from_address_balance = GethDriver.client.call('eth_getBalance', [from_address, 'latest']).to_i(16)
    
    create_and_import_block(
      facet_data: "0x",
      to_address: counter_address,
      from_address: from_address,
      value: from_address_balance + 1,
      eth_gas_used: 0,
      expect_failure: true
    )
  end
end
