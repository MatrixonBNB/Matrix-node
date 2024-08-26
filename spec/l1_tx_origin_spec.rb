require "rails_helper"

RSpec.describe "L1 Tx Origin Gas Delegation" do
  let!(:deployer_address) { "0x8b7d37DE8E58C3c33e7cef70F92ABC1879c4EE73" }
  let!(:from_address) { "0x1111" + SecureRandom.hex(18) }
  let!(:from_address2) { "0x2222" + SecureRandom.hex(18) }
  
  let!(:counter_address) {
    facet_data = EVMHelpers.get_deploy_data('contracts/Counter', [1])
            
    res = create_and_import_block(
      facet_data: facet_data,
      to_address: nil,
      from_address: deployer_address
    )
    
    res.receipts_imported.first.contract_address
  }
  
  it 'handles refunds correctly for internal calls' do
    # Setup
    increment_input = TransactionHelper.get_function_calldata(
      contract: 'contracts/Counter', function: 'increment', args: []
    )
    consume_gas_input = TransactionHelper.get_function_calldata(
      contract: 'contracts/Counter', function: 'consumeGas', args: [5_000, "a" * 1_000]
    )
    
    initial_from_address_balance = GethDriver.client.call('eth_getBalance', [from_address, 'latest']).to_i(16)
    initial_from_address2_balance = GethDriver.client.call('eth_getBalance', [from_address2, 'latest']).to_i(16)
    
    expect(initial_from_address_balance).to eq(0)
    expect(initial_from_address2_balance).to eq(0)
    
    # Execute transaction
    res = call_contract_function(
      contract: 'contracts/Counter',
      address: counter_address,
      from: from_address,
      function: 'increment',
      gas_limit: 500_000,
      sub_calls: [
        {
          to: counter_address,
          from: from_address2,
          input: consume_gas_input,
          gas_limit: 600_000
        }
      ]
    )
    
    # Get final balances
    final_from_address_balance = GethDriver.client.call('eth_getBalance', [from_address, 'latest']).to_i(16)
    final_from_address2_balance = GethDriver.client.call('eth_getBalance', [from_address2, 'latest']).to_i(16)

    base_fee = GethDriver.client.call("eth_getBlockByNumber", ["latest", false])['baseFeePerGas'].to_i(16)
    
    outer_tx = res.transactions_imported.first
    outer_receipt = res.receipts_imported.first
    inner_tx = res.transactions_imported.second
    inner_receipt = res.receipts_imported.second
    
    # Outer transaction
    outer_mint = outer_tx.mint
    outer_gas_cost = outer_tx.gas_limit * base_fee
    outer_gas_refund = (outer_tx.gas_limit - outer_receipt.gas_used) * base_fee
    outer_balance_change = outer_mint - outer_gas_cost + outer_gas_refund

    # Inner transaction
    inner_mint = inner_tx.mint
    inner_gas_cost = inner_tx.gas_limit * base_fee
    inner_gas_refund = (inner_tx.gas_limit - inner_receipt.gas_used) * base_fee
    
    excess_inner_mint = inner_mint - inner_gas_cost
    
    expected_from_address_balance_change = outer_balance_change + inner_gas_refund + excess_inner_mint

    actual_from_address_balance_change = final_from_address_balance - initial_from_address_balance

    # Print detailed debug information
    puts "Base fee: #{base_fee}"
    puts "Outer transaction: Gas used: #{outer_receipt.gas_used}, Gas limit: #{outer_tx.gas_limit}, Mint: #{outer_mint}"
    puts "Inner transaction: Gas used: #{inner_receipt.gas_used}, Gas limit: #{inner_tx.gas_limit}, Mint: #{inner_mint}"
    puts "Outer balance change: #{outer_balance_change}"
    puts "Inner gas refund: #{inner_gas_refund}"
    puts "Expected from_address balance change: #{expected_from_address_balance_change}"
    puts "Actual from_address balance change: #{actual_from_address_balance_change}"
    puts "Difference: #{actual_from_address_balance_change - expected_from_address_balance_change}"
    
    # Expectations
    expect(actual_from_address_balance_change).to eq(expected_from_address_balance_change)
    
    expect(outer_receipt.effective_gas_price).to eq(base_fee)
  end
end