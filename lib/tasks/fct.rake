namespace :fct do
  desc "Display FCT fork parameters"
  task fork_parameters: :environment do
    puts "FCT Fork Parameters:"
    puts "-" * 50
    
    parameters = FctMintCalculator.fork_parameters
    
    puts "Total Minted at Fork:     #{(parameters[0] / 1e18).round(2)} FCT"
    puts "Max Supply:               #{(parameters[1] / 1e18).round(2)} FCT"
    puts "Target per Period:        #{(parameters[2] / 1e18).round(2)} FCT"
    
    puts "\nMinting Constants:"
    puts "Period Length:              #{FctMintCalculator::ADJUSTMENT_PERIOD_TARGET_LENGTH.to_i} blocks"
    puts "Max Mint Rate:              #{FctMintCalculator::MAX_MINT_RATE.to_i}"
    puts "Min Mint Rate:              #{FctMintCalculator::MIN_MINT_RATE.to_i}"
    puts "Max Rate Adjust Up:         #{FctMintCalculator::MAX_RATE_ADJUSTMENT_UP_FACTOR.to_f}x"
    puts "Max Rate Adjust Down:       #{FctMintCalculator::MAX_RATE_ADJUSTMENT_DOWN_FACTOR.to_f}x"
    puts "First Halving Target:       #{(FctMintCalculator::TARGET_ISSUANCE_FRACTION_FIRST_HALVING.to_f * 100).round(0)}% of supply"
    puts "Target blocks per Halving:  #{FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING.to_i}"
    puts "Target periods per Halving: #{FctMintCalculator.target_num_periods_in_halving.to_f.round(2)}"
    puts "Fork Block Number:          #{SysConfig.bluebird_fork_block_number}"
    
    if SysConfig.bluebird_immediate_fork?
      puts "\nMode: Immediate Fork (using environment variables)"
    else
      puts "\nMode: Scheduled Fork (calculated from historical data)"
    end
  end
end