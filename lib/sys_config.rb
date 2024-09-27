module SysConfig
  extend self
  
  FACET_INBOX_ADDRESS = "0x00000000000000000000000000000000000face7".freeze
  L2_BLOCK_GAS_LIMIT = 300e6.to_i
  PER_L2_TX_GAS_LIMIT = 50_000_000
  INITIAL_FCT_MINT_PER_L1_GAS = 4096.gwei
  
  def l1_genesis_block
    ENV.fetch("START_BLOCK").to_i - 1
  end
  
  def v2_fork_block
    ENV.fetch("V2_FORK_BLOCK").to_i
  end
  
  def v2_fork_timestamp
    # TODO: probably should use timestamp to avoid ambiguity with missed L1 slots
  end
  
  # TODO: Fix this so it works with missed L1 slots
  def facet_v2_fork_block_number
    first_l1_block_number = l1_genesis_block
    first_v2_l1_block_number = v2_fork_block
    
    first_v2_l1_block_number - first_l1_block_number
  end
  
  def facet_block_in_v1?(facet_block_number)
    facet_block_number < facet_v2_fork_block_number
  end
  
  def eth_block_in_v1?(eth_block_number)
    !eth_block_in_v2?(eth_block_number)
  end
  
  def eth_block_in_v2?(eth_block_number)
    eth_block_number >= v2_fork_block
  end
end
