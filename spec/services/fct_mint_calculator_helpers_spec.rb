require 'rails_helper'

RSpec.describe FctMintCalculator do
  let(:client) { instance_double('GethClient') }
  
  before do
    allow(FctMintCalculator).to receive(:client).and_return(client)
    # Default stub to prevent nil errors
    allow(client).to receive(:get_l1_attributes).and_return(nil)
  end

  describe '.calculate_historical_total' do
    it 'sums two complete periods and a partial period' do
      original_period_length = FctMintCalculator::ORIGINAL_ADJUSTMENT_PERIOD_TARGET_LENGTH.to_i
      
      # Period 1: blocks 0-9999
      allow(client).to receive(:get_l1_attributes).with(original_period_length - 1).and_return({
        fct_mint_period_l1_data_gas: 50_000,
        fct_mint_rate: 2
      })
      
      # Period 2: blocks 10000-19999  
      allow(client).to receive(:get_l1_attributes).with(original_period_length * 2 - 1).and_return({
        fct_mint_period_l1_data_gas: 60_000,
        fct_mint_rate: 3
      })
      
      # Partial period: blocks 20000-24999
      allow(client).to receive(:get_l1_attributes).with(original_period_length * 2.5 - 1).and_return({
        fct_mint_period_l1_data_gas: 20_000,
        fct_mint_rate: 4
      })
      
      total = described_class.calculate_historical_total((original_period_length * 2.5).to_i)
      expect(total).to eq(50_000 * 2 + 60_000 * 3 + 20_000 * 4) # 360,000
    end

    it 'handles missing attributes gracefully' do
      original_period_length = FctMintCalculator::ORIGINAL_ADJUSTMENT_PERIOD_TARGET_LENGTH.to_i
      
      allow(client).to receive(:get_l1_attributes).with(original_period_length - 1).and_return({
        fct_mint_period_l1_data_gas: 50_000,
        fct_mint_rate: 2
      })
      
      # Second period returns nil (already stubbed as default)
      
      allow(client).to receive(:get_l1_attributes).with(original_period_length * 2.5 - 1).and_return({
        fct_mint_period_l1_data_gas: 20_000,
        fct_mint_rate: 4
      })
      
      total = described_class.calculate_historical_total((original_period_length * 2.5).to_i)
      expect(total).to eq(50_000 * 2 + 20_000 * 4) # 180,000
    end

    it 'returns correct total when fork is exactly on period boundary' do
      original_period_length = FctMintCalculator::ORIGINAL_ADJUSTMENT_PERIOD_TARGET_LENGTH.to_i
      
      # Fork at block 20,000 - exactly 2 complete periods
      allow(client).to receive(:get_l1_attributes).with(original_period_length - 1).and_return({
        fct_mint_period_l1_data_gas: 50_000,
        fct_mint_rate: 2
      })
      
      allow(client).to receive(:get_l1_attributes).with(original_period_length * 2 - 1).and_return({
        fct_mint_period_l1_data_gas: 60_000,
        fct_mint_rate: 3
      })
      
      total = described_class.calculate_historical_total(original_period_length * 2)
      expect(total).to eq(50_000 * 2 + 60_000 * 3) # 280,000
    end
  end

  describe 'fork block parameter computation' do
    it 'raises when block_number is 0' do
      allow(SysConfig).to receive(:bluebird_fork_block_number).and_return(0)
      allow(SysConfig).to receive(:bluebird_immediate_fork?).and_return(false)
      allow(described_class).to receive(:bluebird_fork_block_total_minted).and_return(0)
      
      expect {
        described_class.compute_max_supply
      }.to raise_error(/expected mint percentage is zero/)
    end
    
    it 'calculates correct parameters for normal case' do
      fork_block = 1_182_600
      total_minted_at_fork = 140_000_000
      
      allow(SysConfig).to receive(:bluebird_fork_block_number).and_return(fork_block)
      allow(SysConfig).to receive(:bluebird_immediate_fork?).and_return(false)
      allow(described_class).to receive(:bluebird_fork_block_total_minted).and_return(total_minted_at_fork)
      
      max_supply = described_class.compute_max_supply
      initial_target = described_class.compute_target_per_period
      
      # Calculate expected max supply based on the formula in compute_max_supply
      percent_time_elapsed = Rational(fork_block) / FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING
      expected_mint_percentage = percent_time_elapsed * FctMintCalculator::TARGET_ISSUANCE_FRACTION_FIRST_HALVING
      expected_max_supply = (total_minted_at_fork / expected_mint_percentage).to_i
      
      expect(max_supply).to eq(expected_max_supply)
      
      # Calculate expected initial target based on the formula in compute_target_per_period
      expected_periods = FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING / FctMintCalculator::ADJUSTMENT_PERIOD_TARGET_LENGTH
      expected_initial_target = (expected_max_supply / 2) / expected_periods
      expect(initial_target).to be_within(1).of(expected_initial_target)
    end
  end

  describe '.issuance_on_pace_delta' do
    before do
      # Set up a consistent fork scenario for these tests
      fork_block = 1_182_600
      total_minted_at_fork = 140_000_000
      
      allow(SysConfig).to receive(:bluebird_fork_block_number).and_return(fork_block)
      allow(SysConfig).to receive(:bluebird_immediate_fork?).and_return(false)
      allow(described_class).to receive(:bluebird_fork_block_total_minted).and_return(total_minted_at_fork)
      
      # Let the actual methods calculate the values based on the setup
      @max_supply = described_class.compute_max_supply
      @initial_target = described_class.compute_target_per_period
      
      # Now stub them to return these calculated values
      allow(described_class).to receive(:compute_max_supply).and_return(@max_supply)
      allow(described_class).to receive(:compute_target_per_period).and_return(@initial_target)
    end

    it 'returns positive delta when ahead of schedule' do
      allow(client).to receive(:get_l1_attributes).with(1_000_000).and_return({
        fct_total_minted: 150_000_000 # Ahead of schedule
      })
      
      delta = described_class.issuance_on_pace_delta(1_000_000)
      expect(delta).to be > 0
    end

    it 'returns negative delta when behind schedule' do
      allow(client).to receive(:get_l1_attributes).with(1_000_000).and_return({
        fct_total_minted: 100_000_000 # Behind schedule
      })
      
      delta = described_class.issuance_on_pace_delta(1_000_000)
      expect(delta).to be < 0
    end

    it 'falls back to calculate_historical_total when attrs missing' do
      # nil already stubbed as default
      allow(described_class).to receive(:calculate_historical_total).with(1_000_000).and_return(120_000_000)
      
      delta = described_class.issuance_on_pace_delta(1_000_000)
      expect(delta).to be_a(Float)
    end

    it 'raises when block_number is 0' do
      expect {
        described_class.issuance_on_pace_delta(0)
      }.to raise_error(/Time fraction is zero/)
    end
  end
end