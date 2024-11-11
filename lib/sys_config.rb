module SysConfig
  extend self
  
  FACET_INBOX_ADDRESS = "0x00000000000000000000000000000000000face7".freeze
  L2_BLOCK_GAS_LIMIT = Integer(ENV.fetch('L2_BLOCK_GAS_LIMIT', 240_000_000))
  L2_BLOCK_TIME = 12
  
  def block_gas_limit(block)
    if in_migration_mode?
      5_000_000_000
    elsif is_first_v2_block?(block)
      # TODO
      L2_BLOCK_GAS_LIMIT * 20
    else
      L2_BLOCK_GAS_LIMIT
    end
  end
  
  def l1_genesis_block_number
    ENV.fetch("L1_GENESIS_BLOCK").to_i
  end
  
  def genesis_timestamp
    @_genesis_timestamp ||= EthRpcClient.l1.get_block(l1_genesis_block_number)["timestamp"].to_i(16)
  end
  
  def in_migration_mode?
    return false if [nil, "false"].include?(ENV['MIGRATION_MODE'])
    return true if ENV['MIGRATION_MODE'] == "true"
    raise "Invalid MIGRATION_MODE value: #{ENV['MIGRATION_MODE']}"
  end
  
  def in_v2?
    !in_migration_mode?
  end
  
  def is_first_v2_block?(block)
    in_v2? && block.number == 1
  end
  
  def is_second_v2_block?(block)
    in_v2? && block.number == 2
  end
end
