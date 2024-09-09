require "rails_helper"

RSpec.describe FctMintCalculator do
  let(:block_base_fee) { 10.gwei }  # Example base fee in ether per gas unit

  describe '#calculate_fct_minted_in_block' do
    it 'calculates the correct FCT for a given gas usage and base fee' do
      gas_units_used = 21000
      fct_minted = FctMintCalculator.calculate_fct_minted_in_block(gas_units_used, block_base_fee)

      expect(fct_minted).to be > 0
      expect(fct_minted).to be_a(Numeric)
    end

    it 'caps the FCT minted at approximately 1 FCT when large amounts of gas are burned' do
      large_gas_units_used = 100e7.to_i # Large gas usage
      max_fct = FctMintCalculator.max_total_fct_minted_per_block_in_first_period
      fct_minted = FctMintCalculator.calculate_fct_minted_in_block(large_gas_units_used, block_base_fee)
      
      # TODO: use fixed precision
      epsilon = 0.000001
      
      expect(fct_minted).to be_within(epsilon).of(max_fct)
    end
  end
  
  describe '.assign_mint_amounts' do
    let(:block_base_fee) { 10.gwei }

    let(:facet_txs) do
      [
        instance_double('FacetTransaction', l1_calldata_gas_used: 21000, mint: 0),
        instance_double('FacetTransaction', l1_calldata_gas_used: 50000, mint: 0),
        instance_double('FacetTransaction', l1_calldata_gas_used: 100000, mint: 0)
      ]
    end

    before do
      facet_txs.each do |tx|
        allow(tx).to receive(:mint=)
      end
    end

    it 'assigns FCT mints based on calldata gas used in each transaction' do
      total_l1_calldata_gas_used = facet_txs.sum(&:l1_calldata_gas_used)
      total_fct_minted = FctMintCalculator.calculate_fct_minted_in_block(total_l1_calldata_gas_used, block_base_fee)
      
      FctMintCalculator.assign_mint_amounts(facet_txs, block_base_fee)

      expected_mints = facet_txs.map do |tx|
        tx.l1_calldata_gas_used * total_fct_minted / total_l1_calldata_gas_used
      end

      facet_txs.zip(expected_mints).each do |tx, expected_mint|
        expect(tx).to have_received(:mint=).with(expected_mint)
      end

      total_assigned_mint = expected_mints.sum
      expect(total_assigned_mint).to be_within(facet_txs.length).of(total_fct_minted)
    end
  end
end
