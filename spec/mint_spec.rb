require "rails_helper"

RSpec.describe "Minting" do
  let(:block_base_fee) { 10.gwei }  # Example base fee in ether per gas unit

  describe '#calculate_fct_minted_in_block' do
    it 'calculates the correct FCT for a given gas usage and base fee' do
      gas_units_used = 21000
      fct_minted = FctMintCalculator.calculate_fct_minted_in_block(gas_units_used, block_base_fee)

      expect(fct_minted).to be > 0
      expect(fct_minted).to be_a(Numeric)
    end

    it 'caps the FCT minted at approximately 1 FCT when large amounts of gas are burned' do
      large_gas_units_used = 1e90.to_i # Large gas usage
      max_fct = FctMintCalculator.max_total_fct_minted_per_block_in_first_period
      fct_minted = FctMintCalculator.calculate_fct_minted_in_block(large_gas_units_used, block_base_fee)
      
      # TODO: use fixed precision
      epsilon = 0.000001
      
      expect(fct_minted).to be_within(epsilon).of(max_fct)
    end
  end

  describe '#calculate_fct_for_transactions' do
    let(:transactions) do
      [
        { tx_id: 1, gas_used: 21000 },
        { tx_id: 2, gas_used: 50000 },
        { tx_id: 3, gas_used: 100000 }
      ].map { |tx| tx[:gas_used] }
    end

    it 'distributes FCT incrementally based on gas used in each transaction' do
      fct_awards = FctMintCalculator.calculate_fct_for_transactions(transactions, block_base_fee)

      expect(fct_awards).to be_an(Array)
      expect(fct_awards.size).to eq(3)
      
      fct_awards.each.with_index do |award, i|
        expect(award).to be_a(Numeric)
        expect(award).to be > 0
        expect(award).to be > (block_base_fee * transactions[i])
      end
    end

    it 'ensures that the total FCT minted does not exceed the max per block' do
      fct_awards = FctMintCalculator.calculate_fct_for_transactions(transactions, block_base_fee)

      total_fct_awarded = fct_awards.sum
      max_fct = FctMintCalculator.max_total_fct_minted_per_block_in_first_period
      
      expect(total_fct_awarded).to be <= max_fct
    end
  end
end
