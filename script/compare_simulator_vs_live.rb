#!/usr/bin/env ruby

require_relative '../config/environment'

# Compare FCT simulator output with live Geth data
# This will help identify where the simulator diverges

class SimulatorComparison
  def self.run(blocks_to_check: 1000, verbose: false)
    puts "Comparing FCT simulator with live Geth data"
    puts "="*60
    
    # Create simulator from fork
    sim = FctMintSimulatorSimple.from_fork
    
    # Track divergences
    divergences = []
    first_divergence = nil
    
    puts "\nChecking #{blocks_to_check} blocks..."
    
    blocks_to_check.times do |i|
      block_num = 3 + i  # Start from block 3 (first block after fork)
      
      # Simulate one block
      sim.simulate_single_block(verbose: false)
      
      # Get simulator state
      sim_attrs = sim.instance_variable_get(:@simulated_attributes)[block_num]
      
      # Get live Geth state
      begin
        geth_attrs = GethDriver.client.get_l1_attributes(block_num)
      rescue => e
        puts "\nError getting Geth data for block #{block_num}: #{e.message}"
        break
      end
      
      # Compare key attributes
      diverged = false
      diffs = []
      
      if sim_attrs[:fct_total_minted] != geth_attrs[:fct_total_minted]
        diverged = true
        sim_fct = sim_attrs[:fct_total_minted] / 1e18.to_f
        geth_fct = geth_attrs[:fct_total_minted] / 1e18.to_f
        diff_fct = sim_fct - geth_fct
        diff_pct = (diff_fct / geth_fct * 100).round(3)
        diffs << "total_minted: #{sim_fct.round(6)} vs #{geth_fct.round(6)} FCT (#{diff_pct}%)"
      end
      
      if sim_attrs[:fct_mint_rate] != geth_attrs[:fct_mint_rate]
        diverged = true
        diffs << "mint_rate: #{sim_attrs[:fct_mint_rate]} vs #{geth_attrs[:fct_mint_rate]} wei FCT/gas"
      end
      
      if sim_attrs[:fct_period_start_block] != geth_attrs[:fct_period_start_block]
        diverged = true
        diffs << "period_start: #{sim_attrs[:fct_period_start_block]} vs #{geth_attrs[:fct_period_start_block]}"
      end
      
      if sim_attrs[:fct_period_minted] != geth_attrs[:fct_period_minted]
        diverged = true
        sim_period = sim_attrs[:fct_period_minted] / 1e18.to_f
        geth_period = geth_attrs[:fct_period_minted] / 1e18.to_f
        diffs << "period_minted: #{sim_period.round(6)} vs #{geth_period.round(6)} FCT"
      end
      
      if diverged
        divergences << {
          block: block_num,
          diffs: diffs,
          sim_attrs: sim_attrs,
          geth_attrs: geth_attrs
        }
        
        if first_divergence.nil?
          first_divergence = block_num
          puts "\n❌ FIRST DIVERGENCE at block #{block_num}!"
          puts "Differences:"
          diffs.each { |d| puts "  - #{d}" }
          
          if verbose
            puts "\nSimulator state:"
            pp sim_attrs
            puts "\nGeth state:"
            pp geth_attrs
          end
        end
      end
      
      # Progress
      if (i + 1) % 100 == 0
        print "\rChecked #{i + 1}/#{blocks_to_check} blocks (#{divergences.length} divergences)..."
      end
    end
    
    puts "\n\n" + "="*60
    puts "COMPARISON SUMMARY"
    puts "="*60
    
    if divergences.empty?
      puts "\n✅ No divergences found! Simulator matches Geth perfectly."
    else
      puts "\n❌ Found #{divergences.length} divergences"
      puts "First divergence at block: #{first_divergence}"
      
      # Check for patterns
      check_divergence_patterns(divergences)
      
      # Check specific issues
      check_zero_mint_rate(divergences)
    end
  end
  
  private
  
  def self.check_divergence_patterns(divergences)
    # Group by type of difference
    total_minted_diffs = divergences.count { |d| d[:diffs].any? { |diff| diff.include?('total_minted') } }
    rate_diffs = divergences.count { |d| d[:diffs].any? { |diff| diff.include?('mint_rate') } }
    period_start_diffs = divergences.count { |d| d[:diffs].any? { |diff| diff.include?('period_start') } }
    
    puts "\nDivergence patterns:"
    puts "  - Total minted differences: #{total_minted_diffs}"
    puts "  - Mint rate differences: #{rate_diffs}"
    puts "  - Period start differences: #{period_start_diffs}"
  end
  
  def self.check_zero_mint_rate(divergences)
    # Check for zero mint rates in simulator
    sim_zero_rates = divergences.count { |d| d[:sim_attrs][:fct_mint_rate] == 0 }
    geth_zero_rates = divergences.count { |d| d[:geth_attrs][:fct_mint_rate] == 0 }
    
    if sim_zero_rates > 0
      puts "\n⚠️  Simulator has ZERO mint rate in #{sim_zero_rates} blocks!"
    end
    
    if geth_zero_rates > 0
      puts "\n⚠️  Geth has ZERO mint rate in #{geth_zero_rates} blocks!"
    end
    
    # Show first few blocks with zero rate
    zero_blocks = divergences.select { |d| d[:sim_attrs][:fct_mint_rate] == 0 }.take(5)
    if zero_blocks.any?
      puts "\nFirst blocks with zero mint rate in simulator:"
      zero_blocks.each do |d|
        puts "  Block #{d[:block]}: sim_rate=0, geth_rate=#{d[:geth_attrs][:fct_mint_rate]}"
      end
    end
  end
end

# Run comparison
if ARGV[0] == '--verbose'
  SimulatorComparison.run(blocks_to_check: ARGV[1]&.to_i || 1000, verbose: true)
else
  SimulatorComparison.run(blocks_to_check: ARGV[0]&.to_i || 1000)
end