require "rails_helper"

RSpec.describe "Transaction Gas Handling" do
  let!(:deployer_address) { "0x8b7d37DE8E58C3c33e7cef70F92ABC1879c4EE73" }
  let!(:from_address) { "0x1111" + SecureRandom.hex(18) }
  
  let!(:counter_address) {
    contract = EVMHelpers.compile_contract('contracts/Counter2')
    facet_data = EVMHelpers.get_deploy_data(contract, [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: deployer_address
    )
    
    res.contract_address
  }
  
  it 'handles gas costs and refunds correctly' do
    contract = EVMHelpers.compile_contract('contracts/Counter2')
    
    initial_balance = GethDriver.client.call('eth_getBalance', [from_address, 'latest']).to_i(16)
    expect(initial_balance).to eq(0)
    
    facet_payload = generate_facet_tx_payload(
      input: "0x" + "1" * 1000,
      to: "0x" + "1" * 40,
      gas_limit: 500_000
    )
    
    events = [
      generate_event_log(facet_payload, from_address, 0),
    ]

    res = import_eth_tx(input: "0x1234", events: events, from_address: from_address)
  
    aliased_from = AddressAliasHelper.apply_l1_to_l2_alias(from_address)
    
    base_fee = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])['baseFeePerGas'].to_i(16)
    
    mint_amount = res.mint
    gas_cost = res.gas * base_fee
    gas_refund = (res.gas - res.gas_used) * base_fee
    
    expected_balance_change = mint_amount - gas_cost + gas_refund
    final_balance = GethDriver.client.call('eth_getBalance', [aliased_from, 'latest']).to_i(16)
    actual_balance_change = final_balance - initial_balance
    
    expect(actual_balance_change).to eq(expected_balance_change)
    expect(res.effective_gas_price).to eq(base_fee)
  end
end