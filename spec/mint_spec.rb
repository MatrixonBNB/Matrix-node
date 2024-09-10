require "rails_helper"

RSpec.describe FctMintCalculator do
  before do
    allow(FacetBlock).to receive(:l1_genesis_block).and_return(1_000_000)
    allow(FacetBlock).to receive(:v2_fork_block).and_return(1_500_000)
  end

  describe '.facet_v2_fork_block_number' do
    it 'calculates the correct V2 fork block number' do
      expect(FctMintCalculator.facet_v2_fork_block_number).to eq(500_000)
    end
  end

  describe '.in_v1?' do
    it 'returns true for blocks before V2 fork' do
      expect(FctMintCalculator.in_v1?(499_999)).to be true
    end

    it 'returns false for blocks after V2 fork' do
      expect(FctMintCalculator.in_v1?(500_000)).to be false
    end
  end

  describe '.calculated_mint_target' do
    it 'returns INITIAL_FCT_PER_BLOCK_MINT_TARGET for V1 blocks' do
      expect(FctMintCalculator.calculated_mint_target(499_999)).to eq(FctMintCalculator::INITIAL_FCT_PER_BLOCK_MINT_TARGET)
    end

    it 'calculates correct mint target for V2 blocks' do
      blocks_in_halving_period = FctMintCalculator::HALVING_PERIOD_IN_BLOCKS
      expect(FctMintCalculator.calculated_mint_target(500_000 + blocks_in_halving_period)).to eq(FctMintCalculator::INITIAL_FCT_PER_BLOCK_MINT_TARGET / 2)
    end
  end

  describe '.calculate_next_block_fct_minted_per_gas' do
    let(:prev_fct_mint_per_gas) { 1000.gwei }
    let(:current_l2_block_number) { 600_000 }

    context 'when prev_total_fct_minted equals target' do
      it 'returns the previous fct_mint_per_gas' do
        target = FctMintCalculator.calculated_mint_target(current_l2_block_number)
        result = FctMintCalculator.calculate_next_block_fct_minted_per_gas(prev_fct_mint_per_gas, target, current_l2_block_number)
        expect(result).to eq(prev_fct_mint_per_gas)
      end
    end

    context 'when prev_total_fct_minted is less than target' do
      it 'increases the fct_mint_per_gas' do
        target = FctMintCalculator.calculated_mint_target(current_l2_block_number)
        result = FctMintCalculator.calculate_next_block_fct_minted_per_gas(prev_fct_mint_per_gas, target - 1.ether, current_l2_block_number)
        expect(result).to be > prev_fct_mint_per_gas
      end
    end

    context 'when prev_total_fct_minted is greater than target' do
      it 'decreases the fct_mint_per_gas' do
        target = FctMintCalculator.calculated_mint_target(current_l2_block_number)
        result = FctMintCalculator.calculate_next_block_fct_minted_per_gas(prev_fct_mint_per_gas, target + 1.ether, current_l2_block_number)
        expect(result).to be < prev_fct_mint_per_gas
      end
    end
  end

  describe '.assign_mint_amounts' do
    let(:facet_block) { double('FacetBlock', number: 600_000) }
    let(:facet_tx) { double('FacetTx', l1_calldata_gas_used: 100_000) }

    context 'in V1' do
      before do
        allow(FctMintCalculator).to receive(:in_v1?).and_return(true)
      end

      it 'assigns fixed mint amount and uses initial values' do
        expect(facet_tx).to receive(:mint=).with(10.ether)
        expect(facet_block).to receive(:assign_attributes).with(
          total_fct_minted: FctMintCalculator::INITIAL_FCT_PER_BLOCK_MINT_TARGET,
          fct_mint_per_gas: FctMintCalculator::INITIAL_FCT_MINT_PER_GAS
        )

        FctMintCalculator.assign_mint_amounts([facet_tx], facet_block)
      end
    end

    context 'in V2' do
      before do
        allow(FctMintCalculator).to receive(:in_v1?).and_return(false)
        allow(GethDriver.client).to receive(:get_l1_attributes).and_return(
          fct_minted_per_gas: 900.gwei,
          total_fct_minted: 5.ether
        )
      end

      it 'calculates and assigns mint amounts' do
        expect(facet_tx).to receive(:mint=)
        expect(facet_block).to receive(:assign_attributes)

        FctMintCalculator.assign_mint_amounts([facet_tx], facet_block)
      end
    end
  end
end
