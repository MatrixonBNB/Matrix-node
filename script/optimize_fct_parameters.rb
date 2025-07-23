#!/usr/bin/env ruby

require_relative '../config/environment'
require 'csv'

# FCT Parameter Optimization
# Goal: Find parameters that achieve:
# 1. Convergence - supply delta ≲ 2%
# 2. Smoothness - pace delta within ±5%
# 3. Restraint - mint rate doesn't explode

class FctParameterOptimizer
  BLOCKS_TO_SIMULATE = 719_000
  # BLOCKS_TO_SIMULATE = 20_000
  # BLOCKS_TO_SIMULATE = 500000
  SNAP_INTERVAL = 1_000
  
  def self.run
    # Ensure we have cache
    unless File.exist?('tmp/l1_minimal_cache.ndjson')
      puts "Creating minimal cache for #{BLOCKS_TO_SIMULATE} blocks..."
      FctMintSimulator.cache_l1_minimal(BLOCKS_TO_SIMULATE + 10_000)
    end
    
    # Define test matrix
    parameter_sets = build_test_matrix
    
    puts "Starting FCT parameter optimization"
    puts "Testing #{parameter_sets.length} configurations"
    puts "Simulating #{BLOCKS_TO_SIMULATE} blocks each"
    puts "-" * 80
    
    # Run simulations
    results = FctMintSimulator.compare_parameter_snapshots(
      parameter_sets,
      blocks_to_simulate: BLOCKS_TO_SIMULATE,
      snap_interval: SNAP_INTERVAL
    )
    
    # Calculate scores and metrics
    scored_results = calculate_scores(results)
    
    # Generate comprehensive report
    generate_report(scored_results)
    
    # Display visual report
    visual_report(scored_results)
    
    # Find and display winner
    display_winner(scored_results)
  end
  
  private
  
  def self.build_test_matrix
    [
      # Baseline
      # { name: 'base' },
      
      # { name: 'up4_dn25', max_up_factor: 4, max_down_factor: 0.25 },
      # { name: 'up4_dn25_p500', max_up_factor: 4, max_down_factor: 0.25, period_length: 500 },
      # { name: 'up4_dn25_p250', max_up_factor: 4, max_down_factor: 0.25, period_length: 250 },
      # { name: 'up3_dn33_p500', max_up_factor: 3, max_down_factor: 0.33, period_length: 500 },
      # { name: 'up5_dn20', max_up_factor: 5, max_down_factor: 0.20 },
      # { name: 'up6_dn17', max_up_factor: 6, max_down_factor: 0.167 },
      
      # { name: 'p750', period_length: 750 },
      # { name: 'p500', period_length: 500 },
      # { name: 'p250', period_length: 250 },
      { name: 'p100', period_length: 100 },
      { name: 'p10', period_length: 10 },
      { name: 'p1', period_length: 1 },
    ]
  end
  
  def self.calculate_scores(results)
    scored = {}
    
    results.each do |name, data|
      snapshots = data[:snapshots]
      final_state = data[:final_state]
      # Skip if no data
      next if snapshots.empty?
      
      # 1. Final supply delta (convergence)
      final_supply_delta = snapshots.last[:supply_delta_pct].abs
      
      # 2. RMS of pace deltas (smoothness)
      pace_deltas = snapshots[1..-1].map { |s| s[:pace_delta_pct] }.compact
      if pace_deltas.any?
        rms_pace = Math.sqrt(pace_deltas.map { |x| x**2 }.sum / pace_deltas.length)
      else
        rms_pace = 0
      end
      
      # 3. Mint rate volatility (restraint)
      mint_rates = snapshots.map { |s| s[:mint_rate] }.compact
      if mint_rates.length > 1
        # Calculate coefficient of variation (CV) - std dev / mean
        mean_rate = mint_rates.sum.to_f / mint_rates.length
        variance = mint_rates.map { |r| (r - mean_rate) ** 2 }.sum / mint_rates.length
        std_dev = Math.sqrt(variance)
        rate_volatility = mean_rate > 0 ? (std_dev / mean_rate * 100) : 0  # As percentage
      else
        rate_volatility = 0
      end
      
      # 4. Additional metrics
      rate_changes = count_rate_changes(snapshots)
      min_period_length = estimate_min_period_length(snapshots, data[:parameters])
      max_pace_delta = pace_deltas.max_by(&:abs) || 0
      within_5pct = pace_deltas.count { |p| p.abs <= 5 }.to_f / pace_deltas.length * 100
      
      # Calculate composite score
      # Lower is better
      score = 0.6 * final_supply_delta +                    # Convergence (want → 0)
              0.3 * rms_pace +                               # Smoothness (want → 0)
              0.1 * rate_volatility.clamp(0, 100)            # Restraint (want stable rates)
      
      scored[name] = {
        parameters: data[:parameters],
        final_supply_delta: final_supply_delta.round(3),
        rms_pace: rms_pace.round(3),
        rate_volatility: rate_volatility.round(2),
        score: score.round(3),
        rate_changes: rate_changes,
        min_period_length: min_period_length,
        max_pace_delta: max_pace_delta.round(3),
        pace_within_5pct: within_5pct.round(1),
        final_total_minted: final_state[:final_total_minted],
        snapshots: snapshots
      }
    end
    
    scored
  end
  
  def self.count_rate_changes(snapshots)
    snapshots.each_cons(2).count { |prev, curr| prev[:mint_rate] != curr[:mint_rate] }
  end
  
  def self.estimate_min_period_length(snapshots, params)
    period_length = params[:period_length] || 1000
    
    # Look for consecutive snapshots where rate changed
    # This indicates a period boundary
    min_blocks = period_length
    
    snapshots.each_cons(2) do |prev, curr|
      if prev[:mint_rate] != curr[:mint_rate]
        blocks_between = curr[:block] - prev[:block]
        min_blocks = [min_blocks, blocks_between].min if blocks_between > 0
      end
    end
    
    min_blocks
  end
  
  def self.print_bar(value, max_value, width = 40, good_threshold = nil)
    return "" if max_value == 0
    
    bar_length = ((value / max_value.to_f) * width).round
    bar = "█" * bar_length + "░" * (width - bar_length)
    
    # Color coding (if terminal supports it)
    if good_threshold
      if value <= good_threshold
        "\e[32m#{bar}\e[0m"  # Green
      elsif value <= good_threshold * 2
        "\e[33m#{bar}\e[0m"  # Yellow
      else
        "\e[31m#{bar}\e[0m"  # Red
      end
    else
      bar
    end
  end
  
  def self.generate_report(scored_results)
    # Sort by score (lower is better)
    sorted = scored_results.sort_by { |_, metrics| metrics[:score] }
    
    # Generate detailed CSV
    CSV.open("tmp/fct_optimization_results.csv", 'w') do |csv|
      csv << [
        "Rank", "Configuration", "Score", "Final Supply Δ%", "RMS Pace Δ%", 
        "Rate Volatility %", "Max Pace Δ%", "Pace Within ±5%", 
        "Rate Changes", "Min Period Length",
        "UP Factor", "Period Length", "DOWN Factor"
      ]
      
      sorted.each_with_index do |(name, metrics), idx|
        params = metrics[:parameters]
        csv << [
          idx + 1,
          name,
          metrics[:score],
          metrics[:final_supply_delta],
          metrics[:rms_pace],
          metrics[:rate_volatility],
          metrics[:max_pace_delta],
          metrics[:pace_within_5pct],
          metrics[:rate_changes],
          metrics[:min_period_length],
          params[:max_up_factor] || 2,
          params[:period_length] || 1000,
          params[:max_down_factor] || 0.5
        ]
      end
    end
    
    # Generate time series CSV for top 5
    CSV.open("tmp/fct_optimization_timeseries.csv", 'w') do |csv|
      headers = ["block"]
      sorted.take(5).each { |(name, _)| headers += ["#{name}_supply_delta", "#{name}_pace_delta"] }
      csv << headers
      
      # Get all unique blocks
      all_blocks = sorted.take(5).flat_map { |(_, m)| m[:snapshots].map { |s| s[:block] } }.uniq.sort
      
      all_blocks.each do |block|
        row = [block]
        sorted.take(5).each do |(name, metrics)|
          snapshot = metrics[:snapshots].find { |s| s[:block] == block }
          if snapshot
            row += [snapshot[:supply_delta_pct], snapshot[:pace_delta_pct]]
          else
            row += [nil, nil]
          end
        end
        csv << row
      end
    end
    
    puts "\nResults saved to:"
    puts "  - tmp/fct_optimization_results.csv (full metrics)"
    puts "  - tmp/fct_optimization_timeseries.csv (top 5 time series)"
  end
  
  def self.visual_report(scored_results)
    sorted = scored_results.sort_by { |_, metrics| metrics[:score] }
    
    puts "\n\nFCT PARAMETER OPTIMIZATION RESULTS"
    puts "="*100
    puts "\nConvergence (Final Supply Delta % - want < 2%)"
    puts "-"*60
    
    max_delta = sorted.map { |_, m| m[:final_supply_delta] }.max
    sorted.each do |name, metrics|
      delta = metrics[:final_supply_delta]
      printf "%-20s %6.2f%% %s\n", name, delta, print_bar(delta, [max_delta, 10].max, 40, 2)
    end
    
    puts "\nSmoothness (RMS Pace Delta % - want < 5%)"
    puts "-"*60
    
    max_rms = sorted.map { |_, m| m[:rms_pace] }.max
    sorted.each do |name, metrics|
      rms = metrics[:rms_pace]
      printf "%-20s %6.2f%% %s\n", name, rms, print_bar(rms, [max_rms, 10].max, 40, 5)
    end
    
    puts "\nRestraint (Rate Volatility % - want < 50%)"
    puts "-"*60
    
    max_volatility = sorted.map { |_, m| m[:rate_volatility] }.max
    sorted.each do |name, metrics|
      volatility = metrics[:rate_volatility]
      printf "%-20s %6.1f%% %s\n", name, volatility, print_bar(volatility, [max_volatility, 100].max, 40, 50)
    end
    
    puts "\nComposite Score (Lower is Better)"
    puts "-"*60
    
    sorted.each_with_index do |(name, metrics), idx|
      score = metrics[:score]
      medal = case idx
              when 0 then "🥇"
              when 1 then "🥈"
              when 2 then "🥉"
              else "  "
              end
      
      printf "%s %-20s %6.2f", medal, name, score
      
      # Show parameter details for top 5
      if idx < 5
        params = metrics[:parameters]
        printf " (UP=%.1f, Period=%d, DOWN=%.2f)", 
               params[:max_up_factor] || 2, 
               params[:period_length] || 1000,
               params[:max_down_factor] || 0.5
      end
      puts
    end
    
    # Parameter insights
    puts "\nPARAMETER INSIGHTS:"
    puts "-"*40
    
    # Group by UP factor
    up_groups = sorted.group_by { |_, m| m[:parameters][:max_up_factor] || 2 }
    puts "\nBy UP Factor:"
    up_groups.sort.each do |up, group|
      metrics_list = group.map { |_, m| m }
      avg_score = metrics_list.map { |m| m[:score] }.sum / metrics_list.length
      avg_delta = metrics_list.map { |m| m[:final_supply_delta] }.sum / metrics_list.length
      printf "  UP=%.1f: avg_score=%.2f, avg_supply_δ=%.2f%% (n=%d)\n", up, avg_score, avg_delta, group.length
    end
    
    # Group by period
    period_groups = sorted.group_by { |_, m| m[:parameters][:period_length] || 1000 }
    puts "\nBy Period Length:"
    period_groups.sort.each do |period, group|
      metrics_list = group.map { |_, m| m }
      avg_score = metrics_list.map { |m| m[:score] }.sum / metrics_list.length
      avg_rms = metrics_list.map { |m| m[:rms_pace] }.sum / metrics_list.length
      printf "  Period=%d: avg_score=%.2f, avg_rms_pace=%.2f%% (n=%d)\n", period, avg_score, avg_rms, group.length
    end
  end
  
  def self.display_winner(scored_results)
    # Filter to configurations meeting constraints
    eligible = scored_results.select do |_, metrics|
      metrics[:final_supply_delta] <= 2 &&           # Convergence constraint
      metrics[:rate_volatility] < 50 &&              # Restraint constraint (< 50% volatility)
      metrics[:min_period_length] >= 5               # Sanity check
    end
    
    if eligible.empty?
      puts "\n⚠️  NO CONFIGURATIONS MEET ALL CONSTRAINTS"
      puts "Relaxing to find best available..."
      eligible = scored_results
    end
    
    # Find winner (lowest score among eligible)
    winner_name, winner = eligible.min_by { |_, metrics| metrics[:score] }
    
    puts "\n" + "="*80
    puts "🏆 OPTIMIZATION WINNER: #{winner_name}"
    puts "="*80
    puts "Score: #{winner[:score]}"
    puts "\nMetrics:"
    puts "  - Final supply delta: #{winner[:final_supply_delta]}%"
    puts "  - RMS pace delta: #{winner[:rms_pace]}%"
    puts "  - Rate volatility: #{winner[:rate_volatility]}%"
    puts "  - Pace within ±5%: #{winner[:pace_within_5pct]}% of time"
    puts "  - Rate adjustments: #{winner[:rate_changes]}"
    puts "\nParameters:"
    params = winner[:parameters]
    puts "  - UP factor: #{params[:max_up_factor] || 2}"
    puts "  - Period length: #{params[:period_length] || 1000}"
    puts "  - DOWN factor: #{params[:max_down_factor] || 0.5}"
    
    # Show top 5
    puts "\n" + "-"*40
    puts "Top 5 configurations by score:"
    scored_results.sort_by { |_, m| m[:score] }.take(5).each_with_index do |(name, metrics), idx|
      puts "#{idx + 1}. #{name}: score=#{metrics[:score]}, supply_δ=#{metrics[:final_supply_delta]}%, rms_pace=#{metrics[:rms_pace]}%"
    end
  end
end

# Run the optimization
if __FILE__ == $0
  FctParameterOptimizer.run
end
