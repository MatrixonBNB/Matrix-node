require "rails_helper"

RSpec.describe "L1 Tx Origin Gas Delegation" do
  let!(:deployer_address) { "0x8b7d37DE8E58C3c33e7cef70F92ABC1879c4EE73" }
  let!(:from_address) { "0x1111" + SecureRandom.hex(18) }
  let!(:from_address2) { "0x2222" + SecureRandom.hex(18) }
  
  let!(:counter_address) {
    contract = EVMHelpers.compile_contract('contracts/Counter')
    facet_data = EVMHelpers.get_deploy_data(contract, [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: deployer_address
    )
    
    res.contract_address
  }
  
  it 'handles refunds correctly for internal calls' do
    contract = EVMHelpers.compile_contract('contracts/Counter')
    
    increment_input = TransactionHelper.get_function_calldata(
      contract: contract, function: 'increment', args: []
    )
    consume_gas_input = TransactionHelper.get_function_calldata(
      contract: contract, function: 'consumeGas', args: [5_000, "a" * 1_000]
    )
    
    l1_tx_origin = from_address
    facet_from = from_address2
    
    initial_l1_tx_origin_balance = GethDriver.client.call('eth_getBalance', [l1_tx_origin, 'latest']).to_i(16)
    initial_facet_from_balance = GethDriver.client.call('eth_getBalance', [facet_from, 'latest']).to_i(16)
    
    expect(initial_l1_tx_origin_balance).to eq(0)
    expect(initial_facet_from_balance).to eq(0)
    
    facet_payload = generate_facet_tx_payload(
      input: "0x" + "1" * 1000,
      to: "0x" + "1" * 40,
      gas_limit: 500_000
    )
    
    events = [
      generate_event_log(facet_payload, facet_from, 0),
    ]

    res = import_eth_tx(input: "0x1234", events: events, from_address: l1_tx_origin)
    
    base_fee = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])['baseFeePerGas'].to_i(16)
    
    mint_amount = res.mint
    
    gas_cost = res.gas * base_fee
    gas_refund = (res.gas - res.gas_used) * base_fee
    
    expected_facet_from_balance_change = 0
    expected_l1_tx_origin_balance_change = mint_amount - gas_cost + gas_refund
    
    final_l1_tx_origin_balance = GethDriver.client.call('eth_getBalance', [l1_tx_origin, 'latest']).to_i(16)
    final_facet_from_balance = GethDriver.client.call('eth_getBalance', [facet_from, 'latest']).to_i(16)
    
    actual_l1_tx_origin_balance_change = final_l1_tx_origin_balance - initial_l1_tx_origin_balance
    actual_facet_from_balance_change = final_facet_from_balance - initial_facet_from_balance

    expect(actual_l1_tx_origin_balance_change).to eq(expected_l1_tx_origin_balance_change)
    expect(actual_facet_from_balance_change).to eq(expected_facet_from_balance_change)
      
    expect(res.effective_gas_price).to eq(base_fee)
  end
end