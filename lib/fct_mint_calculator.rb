module FctMintCalculator
  extend self
  
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  SECONDS_PER_BLOCK = 12
  HALVING_PERIOD_LENGTH = 4 * SECONDS_PER_YEAR
  HALVING_PERIOD_IN_BLOCKS = HALVING_PERIOD_LENGTH / SECONDS_PER_BLOCK

  INITIAL_FCT_MINT_PER_GAS = 1000.gwei
  INITIAL_FCT_PER_BLOCK_MINT_TARGET = 10.ether
  FCT_PER_BLOCK_MINT_CHANGE_DENOMINATOR = 8

  def calculated_mint_target(current_l2_block_number)
    if in_v1?(current_l2_block_number)
      return INITIAL_FCT_PER_BLOCK_MINT_TARGET
    end
    
    blocks_since_v2_fork = current_l2_block_number - facet_v2_fork_block_number
  
    halving_periods_passed = blocks_since_v2_fork / HALVING_PERIOD_IN_BLOCKS
  
    current_mint_target = INITIAL_FCT_PER_BLOCK_MINT_TARGET / (2 ** halving_periods_passed)
    
    current_mint_target
  end
  
  def calculate_next_block_fct_minted_per_gas(
    prev_fct_mint_per_gas,
    prev_total_fct_minted,
    current_l2_block_number
  )
    fct_per_block_mint_target = calculated_mint_target(current_l2_block_number)
  
    if prev_total_fct_minted == fct_per_block_mint_target
      return prev_fct_mint_per_gas
    end
    
    denom = fct_per_block_mint_target * FCT_PER_BLOCK_MINT_CHANGE_DENOMINATOR

    if prev_total_fct_minted < fct_per_block_mint_target
      num = prev_fct_mint_per_gas * (fct_per_block_mint_target - prev_total_fct_minted)
      rate_delta = [num / denom, 1].max
      next_rate = prev_fct_mint_per_gas + rate_delta
    else
      num = prev_fct_mint_per_gas * (prev_total_fct_minted - fct_per_block_mint_target)
      rate_delta = num / denom
      next_rate = [prev_fct_mint_per_gas - rate_delta, 0].max
    end
    
    next_rate
  end
  
  def assign_mint_amounts(facet_txs, facet_block)
    if in_v1?(facet_block.number)
      facet_txs.each do |tx|
        # The mint amount doesn't matter as the excess will be burned
        tx.mint = 10.ether
      end
      
      total_fct_minted = calculated_mint_target(facet_block.number)
      fct_mint_per_gas = INITIAL_FCT_MINT_PER_GAS
    else
      prev_l2_block_number = facet_block.number - 1
      prev_l1_attributes = GethDriver.client.get_l1_attributes(prev_l2_block_number)
    
      prev_fct_mint_per_gas = prev_l1_attributes[:fct_minted_per_gas]
      prev_total_fct_minted = prev_l1_attributes[:total_fct_minted]
      
      fct_mint_per_gas = calculate_next_block_fct_minted_per_gas(
        prev_fct_mint_per_gas,
        prev_total_fct_minted,
        facet_block.number
      )
      
      total_l1_calldata_gas_used = facet_txs.sum(&:l1_calldata_gas_used)
      
      total_fct_minted = fct_mint_per_gas * total_l1_calldata_gas_used
      
      facet_txs.each do |tx|
        tx.mint = tx.l1_calldata_gas_used * fct_mint_per_gas
      end
    end
    
    facet_block.assign_attributes(
      total_fct_minted: total_fct_minted,
      fct_mint_per_gas: fct_mint_per_gas
    )
    
    nil
  end
  
  def facet_v2_fork_block_number
    first_l1_block_number = FacetBlock.l1_genesis_block
    first_v2_l1_block_number = FacetBlock.v2_fork_block
    
    first_v2_l1_block_number - first_l1_block_number
  end
  
  def in_v1?(facet_block_number)
    facet_block_number < facet_v2_fork_block_number
  end
end
