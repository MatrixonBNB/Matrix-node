module FctMintCalculator
  extend SysConfig
  include SysConfig
  extend self
  
  ADJUSTMENT_PERIOD = 10_000 # blocks
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  HALVING_PERIOD_IN_SECONDS = 1 * SECONDS_PER_YEAR
  
  RAW_HALVING_PERIOD_IN_BLOCKS = HALVING_PERIOD_IN_SECONDS / SysConfig::L2_BLOCK_TIME
  ADJUSTMENT_PERIODS_PER_HALVING = RAW_HALVING_PERIOD_IN_BLOCKS / ADJUSTMENT_PERIOD
  
  HALVING_PERIOD_IN_BLOCKS = ADJUSTMENT_PERIOD * ADJUSTMENT_PERIODS_PER_HALVING
  
  TARGET_FCT_MINT_PER_L1_BLOCK = 64.ether
  TARGET_MINT_PER_PERIOD = TARGET_FCT_MINT_PER_L1_BLOCK * ADJUSTMENT_PERIOD
  MAX_ADJUSTMENT_FACTOR = 2
  BASE_RATE = 10_000_000.gwei
  MAX_RATE = BASE_RATE
  MIN_RATE = 1
  
  def halving_periods_passed(current_l2_block)
    current_l2_block.number / HALVING_PERIOD_IN_BLOCKS
  end
  
  def halving_factor(l2_block)
    2 ** halving_periods_passed(l2_block)
  end
  
  def is_first_block_in_period?(l2_block)
    l2_block.number % ADJUSTMENT_PERIOD == 0
  end
  
  def halving_adjusted_target(l2_block)
    TARGET_MINT_PER_PERIOD / halving_factor(l2_block)
  end

  def compute_new_rate(facet_block, prev_rate, cumulative_mint_in_period)
    if is_first_block_in_period?(facet_block)
      if cumulative_mint_in_period == 0
        new_rate = MAX_RATE
      else
        halving_adjusted_target = halving_adjusted_target(facet_block)
        return 0 if halving_adjusted_target == 0
        
        new_rate = halving_adjusted_target / cumulative_mint_in_period
      end

      max_allowed_rate = [prev_rate * MAX_ADJUSTMENT_FACTOR, MAX_RATE].min
      min_allowed_rate = [prev_rate / MAX_ADJUSTMENT_FACTOR, MIN_RATE].max
      
      new_rate = max_allowed_rate if new_rate > max_allowed_rate
      new_rate = min_allowed_rate if new_rate < min_allowed_rate
    else
      new_rate = prev_rate
    end

    new_rate
  end

  def assign_mint_amounts(facet_txs, facet_block)
    if block_in_v1?(facet_block)
      facet_txs.each { |tx| tx.mint = 1e6.ether }
      
      facet_block.assign_attributes(
        fct_mint_rate: BASE_RATE,
        fct_minted_in_rate_adjustment_period: 0
      )
      
      return
    end
    
    prev_l1_attributes = GethDriver.client.get_l1_attributes(facet_block.number - 1)
    prev_rate = prev_l1_attributes[:fct_mint_rate] 
    cumulative_mint_in_period = prev_l1_attributes[:fct_minted_in_rate_adjustment_period]
    
    new_rate = compute_new_rate(facet_block, prev_rate, cumulative_mint_in_period)
    
    facet_txs.each do |tx|
      tx.mint = tx.l1_calldata_gas_used * new_rate
    end
    
    if is_first_block_in_period?(facet_block)
      new_cumulative_mint = facet_txs.sum(&:mint)
    else
      new_cumulative_mint = cumulative_mint_in_period + facet_txs.sum(&:mint)
    end
    
    facet_block.assign_attributes(
      fct_mint_rate: new_rate,
      fct_minted_in_rate_adjustment_period: new_cumulative_mint
    )
    
    nil
  end
end
