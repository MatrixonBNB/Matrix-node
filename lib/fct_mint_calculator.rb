module FctMintCalculator
  extend self
  
  # TODO: use fixed precision
  MAX_SUPPLY = 21e6.to_i * 1e18.to_i
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  SECONDS_PER_BLOCK = 12
  HALVING_PERIOD_LENGTH = 4 * SECONDS_PER_YEAR

  def calculate_fct_minted_in_block(gas_units_used, block_base_fee)
    ether_burned_in_block = gas_units_used * block_base_fee * 4
    
    x_50 = max_total_fct_minted_per_block_in_first_period / 2
    
    k = Math.log(2) / x_50
    
    max_total_fct_minted_per_block_in_first_period * (1 - Math.exp(-k * ether_burned_in_block))
  end
  
  def calculate_fct_for_transactions(gas_amounts, block_base_fee)
    gas_units_consumed = 0
    
    gas_amounts.map do |gas_used|
      fct_minted_so_far = calculate_fct_minted_in_block(gas_units_consumed, block_base_fee)
      
      gas_units_consumed += gas_used
      
      new_fct_minted = calculate_fct_minted_in_block(gas_units_consumed, block_base_fee)
      
      new_fct_minted - fct_minted_so_far
    end
  end
  
  def max_total_fct_minted_per_block_in_first_period
    issued_in_first_period = MAX_SUPPLY / 2
    
    blocks_per_period = HALVING_PERIOD_LENGTH / SECONDS_PER_BLOCK
    
    issued_in_first_period / blocks_per_period
  end
end
