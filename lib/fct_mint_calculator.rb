module FctMintCalculator
  extend self
  
  MAX_SUPPLY = 21e6.to_i * 1e18.to_i
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  SECONDS_PER_BLOCK = 12
  HALVING_PERIOD_LENGTH = 4 * SECONDS_PER_YEAR
  
  SCALER = 4
  PRECISION_DIGITS = 18

  def calculate_fct_minted_in_block(gas_units_used, block_base_fee)
    ether_burned_in_block = gas_units_used * block_base_fee * SCALER
    
    x_50 = max_total_fct_minted_per_block_in_first_period / 2
    
    log_2 = BigMath.log(2, PRECISION_DIGITS).truncate(PRECISION_DIGITS)
    
    k = log_2 / x_50
    
    exp_term = BigMath.exp(-k * ether_burned_in_block, PRECISION_DIGITS).truncate(PRECISION_DIGITS)
    
    res = max_total_fct_minted_per_block_in_first_period * (1 - exp_term)
    
    res.to_i
  end
  
  def assign_mint_amounts(facet_txs, block_base_fee)
    total_l1_calldata_gas_used = facet_txs.sum(&:l1_calldata_gas_used)
    
    total_fct_minted = calculate_fct_minted_in_block(
      total_l1_calldata_gas_used,
      block_base_fee
    )
    
    facet_txs.each do |tx|
      tx.mint = tx.l1_calldata_gas_used * total_fct_minted / total_l1_calldata_gas_used
    end
  end
  
  def max_total_fct_minted_per_block_in_first_period
    issued_in_first_period = MAX_SUPPLY / 2
    
    blocks_per_period = HALVING_PERIOD_LENGTH / SECONDS_PER_BLOCK
    
    issued_in_first_period / blocks_per_period
  end
end
