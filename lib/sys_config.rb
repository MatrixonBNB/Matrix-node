module SysConfig
  extend self
  
  FACET_INBOX_ADDRESS = "0x00000000000000000000000000000000000face7".freeze
  L2_BLOCK_GAS_LIMIT = Integer(ENV.fetch('L2_BLOCK_GAS_LIMIT', 240_000_000))
  PER_L2_TX_GAS_LIMIT = Integer(ENV.fetch('PER_L2_TX_GAS_LIMIT', 50_000_000))
  INITIAL_FCT_MINT_PER_L1_GAS = 4096.gwei
  L2_BLOCK_TIME = 12
  
  def block_gas_limit(block)
    if block_in_v1?(block)
      L2_BLOCK_GAS_LIMIT * 2
    elsif is_first_v2_block?(block)
      # TODO
      L2_BLOCK_GAS_LIMIT * 10
    else
      L2_BLOCK_GAS_LIMIT
    end
  end
  
  def l1_genesis_block_number
    ENV.fetch("L1_GENESIS_BLOCK").to_i
  end
  
  def v2_fork_timestamp
    ENV.fetch("V2_FORK_TIMESTAMP").to_i
  end
  
  def genesis_timestamp
    @_genesis_timestamp ||= EthRpcClient.l1.get_block(l1_genesis_block_number)["timestamp"].to_i(16)
  end
  
  def l2_v2_fork_block_number
    [(v2_fork_timestamp - genesis_timestamp) / L2_BLOCK_TIME, 0].max
  end
  
  def block_in_v1?(block)
    unless block.respond_to?(:timestamp)
      raise "Invalid block: #{block.inspect}"
    end
    
    block.timestamp < v2_fork_timestamp
  end
  
  def block_in_v2?(block)
    !block_in_v1?(block)
  end
  
  def is_first_v2_block?(block)
    block_in_v2?(block) && block.number == 1
  end
end
