require 'rails_helper'

RSpec.describe "Stress tests" do
  include ActiveSupport::Testing::TimeHelpers
  let(:from_address) { "0x1000000000000000000000000000000000000000" }
  let(:block_gas_limit) { 240_000_000 } # 240M gas limit
  let(:tx_gas_limit) { 50_000_000 } # 50M per-tx gas limit
  
  let!(:gas_burner_contract) { EVMHelpers.compile_contract('GasBurner') }

  let!(:gas_burner_deploy_receipt) { deploy_contract(
    contract: gas_burner_contract,
    from: from_address,
    args: []
  )}
  
  let!(:gas_burner_address) { gas_burner_deploy_receipt.contract_address }
  
  it 'burns gas with multiple calls per block' do
    # Test different numbers of calls per block
    [1, 2, 5, 10, 20, 100, 200, 400, 470, 1000].each do |num_calls|
      puts "\nTesting #{num_calls} gas burn calls in one block"
      
      calls = num_calls.times.map do |i|
        {
          contract: gas_burner_contract,
          address: gas_burner_address,
          from: from_address,
          function: 'burn',
          args: [500_000], # 500k gas burn each
          gas_limit: 500_000 # Give enough headroom
        }
      end
      
      receipts = call_contract_functions(calls)
      
      # Log results
      total_gas_used = 0
      successful_txs = 0
      failed_txs = 0
      
      receipts.each_with_index do |receipt, i|
        if receipt.gas > block_gas_limit - total_gas_used
          expect(receipt.status).to eq(0), "Transaction #{i} should have failed due to insufficient block gas"
          failed_txs += 1
        else
          expect(receipt.status).to eq(1), "Transaction #{i} should have succeeded"
          successful_txs += 1
        end
        
        total_gas_used += receipt.gasUsed
      end
      
      puts "Total gas used: #{total_gas_used}"
      puts "Successful transactions: #{successful_txs}"
      puts "Failed transactions: #{failed_txs}"
      puts "Average gas per successful tx: #{successful_txs > 0 ? total_gas_used / successful_txs : 0}"
      puts "Block number: #{receipts.first.blockNumber}"
      
      # All transactions should be included in block
      expect(receipts.length).to eq(num_calls)
    end
  end
  
  it 'handles gas limits and actual usage correctly' do
    test_scenarios = [
      # First test: Simple case - transactions fit within block
      {
        description: "3 txs that fit in block",
        calls: [
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
          { gas_limit: 100_000, burn_amount: 0 },
          { gas_limit: 100_000, burn_amount: 50_000 },
          { gas_limit: 50_000_000, burn_amount: 50_000_000 },
        ]
      },
      
      # Third test: Actual usage allows more txs than gas limits would suggest
      {
        description: "Actual usage allows more txs",
        calls: [
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 },
          { gas_limit: 45_000_000, burn_amount: 1_000_000 }
        ]
      },
      
      # New test: Transaction exceeds per-tx gas limit
      {
        description: "Tx exceeds per-tx gas limit",
        calls: [
          { gas_limit: 51_000_000, burn_amount: 1_000_000 },  # Should fail (>50M)
          { gas_limit: 40_000_000, burn_amount: 1_000_000 }   # Should succeed
        ]
      }
    ]

    test_scenarios.each do |scenario|
      puts "\nTesting: #{scenario[:description]}"
      
      calls = scenario[:calls].map do |call|
        {
          contract: gas_burner_contract,
          address: gas_burner_address,
          from: from_address,
          function: 'burn',
          args: [call[:burn_amount]],
          gas_limit: call[:gas_limit]
        }
      end
      
      receipts = call_contract_functions(calls)
      
      # Log results
      puts "Number of transactions: #{receipts.length}"
      
      receipts.each_with_index do |receipt, i|
        original_call = scenario[:calls][i]
        
        puts "\nTransaction #{i + 1}:"
        puts "  Gas limit set: #{original_call[:gas_limit]}"
        puts "  Gas actually used: #{receipt.gasUsed}"
        puts "  Status: #{receipt.status == 1 ? 'Success' : 'Failed'}"
        
        # Check both per-tx and block gas limits
        if original_call[:gas_limit] > tx_gas_limit
          expect(receipt.status).to eq(0), "Transaction #{i + 1} should have failed due to exceeding per-tx gas limit"
        elsif receipt.gas > block_gas_limit - receipts[0...i].sum(&:gasUsed)
          expect(receipt.status).to eq(0), "Transaction #{i + 1} should have failed due to insufficient block gas"
        else
          expect(receipt.status).to eq(1), "Transaction #{i + 1} should have succeeded"
        end
      end
      
      puts "\nTotal gas used in block: #{receipts.sum(&:gasUsed)}"
    end
  end
end
