module FctMintCalculator
  extend SysConfig
  include SysConfig
  extend self
  
  SECONDS_PER_YEAR = 31_556_952 # length of a gregorian year (365.2425 days)
  SECONDS_PER_BLOCK = 12
  HALVING_PERIOD_LENGTH = 1 * SECONDS_PER_YEAR
  HALVING_PERIOD_IN_BLOCKS = HALVING_PERIOD_LENGTH / SECONDS_PER_BLOCK
  
  def calculated_fct_mint_per_l1_gas(current_l2_block)
    if block_in_v1?(current_l2_block)
      return INITIAL_FCT_MINT_PER_L1_GAS
    end
    
    INITIAL_FCT_MINT_PER_L1_GAS / (2 ** halving_periods_passed(current_l2_block))
  end
  
  def halving_periods_passed(current_l2_block)
    unless block_in_v2?(current_l2_block)
      raise "Halving only applies to v2 blocks: #{current_l2_block.number}"
    end
    
    blocks_since_v2_fork = current_l2_block.number - l2_v2_fork_block_number
    blocks_since_v2_fork / HALVING_PERIOD_IN_BLOCKS
  end
  
  def assign_mint_amounts(facet_txs, facet_block)
    if block_in_v1?(facet_block)
      facet_txs.each do |tx|
        # The mint amount doesn't matter as the excess will be burned
        tx.mint = 10.ether
      end
    else
      fct_mint_per_gas = calculated_fct_mint_per_l1_gas(facet_block)
      
      facet_txs.each do |tx|
        tx.mint = tx.l1_calldata_gas_used * fct_mint_per_gas
      end
    end
    
    nil
  end
end
