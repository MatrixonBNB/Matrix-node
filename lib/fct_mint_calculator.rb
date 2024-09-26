module FctMintCalculator
  extend self
  
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  SECONDS_PER_BLOCK = 12
  HALVING_PERIOD_LENGTH = 1 * SECONDS_PER_YEAR
  HALVING_PERIOD_IN_BLOCKS = HALVING_PERIOD_LENGTH / SECONDS_PER_BLOCK

  INITIAL_FCT_MINT_PER_L1_GAS = 4096.gwei
  
  def calculated_fct_mint_per_l1_gas(current_l2_block_number)
    if in_v1?(current_l2_block_number)
      return INITIAL_FCT_MINT_PER_L1_GAS
    end
    
    blocks_since_v2_fork = current_l2_block_number - facet_v2_fork_block_number
  
    halving_periods_passed = blocks_since_v2_fork / HALVING_PERIOD_IN_BLOCKS
    
    INITIAL_FCT_MINT_PER_L1_GAS / (2 ** halving_periods_passed)
  end
  
  def assign_mint_amounts(facet_txs, facet_block)
    if in_v1?(facet_block.number)
      facet_txs.each do |tx|
        # The mint amount doesn't matter as the excess will be burned
        tx.mint = 10.ether
      end
    else
      fct_mint_per_gas = calculated_fct_mint_per_l1_gas(facet_block.number)
      
      facet_txs.each do |tx|
        tx.mint = tx.l1_calldata_gas_used * fct_mint_per_gas
      end
    end
    
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
