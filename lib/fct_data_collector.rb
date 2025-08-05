require 'csv'
require 'fileutils'
require 'parallel'
require 'bigdecimal'

class FctDataCollector
  THREAD_COUNT = 30  # Number of parallel threads
  
  # Snapshot analysis configuration
  SNAP = 1000                    # Snapshot interval
  SUPPLY_TOLERANCE = 0.02        # ±2% for cumulative supply
  PACE_TOLERANCE = 0.05          # ±5% for per-snapshot pace
  CONCENTRATION_INTERVAL = 10000 # Check concentration every 10k blocks
  
  def initialize(output_file: 'tmp/fct_raw_data.csv')
    @output_file = output_file
    @fork_block = SysConfig.bluebird_fork_block_number
    @mutex = Mutex.new
  end
  
  def collect
    puts "FCT Data Collector (Parallel)"
    puts "Output: #{@output_file}"
    puts "Threads: #{THREAD_COUNT}"
    puts "-" * 60
    
    # Ensure output directory exists
    FileUtils.mkdir_p(File.dirname(@output_file))
    
    # Get current head
    head_block = EthRpcClient.l2.get_block_number
    puts "Current head: #{head_block}"
    puts "Fork block: #{@fork_block}"
    
    total_blocks = head_block - @fork_block + 1
    puts "Total blocks to process: #{total_blocks}"
    puts "-" * 60
    
    # Delete existing file to start fresh
    FileUtils.rm_f(@output_file)
    
    # Process all blocks in parallel
    start_time = Time.now
    
    # Create progress callback
    progress = 0
    progress_mutex = Mutex.new
    
    # Process all blocks using parallel gem
    results = Parallel.map(@fork_block..head_block, in_threads: THREAD_COUNT) do |block_num|
      result = fetch_fct_details_single(block_num)
      
      # Update progress
      progress_mutex.synchronize do
        progress += 1
        if progress % 1000 == 0
          elapsed = Time.now - start_time
          rate = progress / elapsed
          eta = (total_blocks - progress) / rate
          puts "Processed #{progress}/#{total_blocks} blocks (#{(progress * 100.0 / total_blocks).round(1)}%) - " \
               "#{rate.round(1)} blocks/sec - ETA: #{format_time(eta)}"
        end
      end
      
      result
    end
    
    # Save all results at once
    save_results(results)
    
    puts "\nCollection complete!"
    puts "Total time: #{format_time(Time.now - start_time)}"
    puts "Output saved to: #{@output_file}"
  end
  
  def fetch_fct_details_single(block_num)
    # Create a new client for this thread
    client = EthRpcClient.l2
    
    # Calculate selector for fctDetails()
    selector = '0x' + Eth::Util.keccak256('fctDetails()').first(4).unpack1("H*")
    
    # Make the eth_call
    result = client.eth_call(
      to: FacetTransaction::L1_INFO_ADDRESS.to_hex,
      data: selector,
      block_number: "0x#{block_num.to_s(16)}"
    )
    
    parse_fct_details(block_num, result)
  end
  
  def parse_fct_details(block_num, response)
    unless response.present?
      raise "No response for block #{block_num}"
    end
    
    values = Eth::Abi.decode(
      ['uint128', 'uint128', 'uint128', 'uint128'],
      response
    )
    
    {
      block: block_num,
      mint_rate: values[0],
      total_minted: values[1],
      period_start_block: values[2],
      period_minted: values[3]
    }
  end
  
  def save_results(results)
    # Check if file exists to determine if we need headers
    write_headers = !File.exist?(@output_file)
    
    CSV.open(@output_file, 'a') do |csv|
      csv << %w[block mint_rate total_minted period_start_block period_minted] if write_headers
      
      results.each do |row|
        csv << [
          row[:block],
          row[:mint_rate],
          row[:total_minted],
          row[:period_start_block],
          row[:period_minted]
        ]
      end
    end
  end
  
  def format_time(seconds)
    return "0s" if seconds < 1
    
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = (seconds % 60).to_i
    
    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0
    parts << "#{secs}s" if secs > 0 || parts.empty?
    
    parts.join(" ")
  end
  
  # Snapshot-based analysis at regular intervals
  def snapshot_analysis(input_file: @output_file, output_file: 'tmp/fct_snapshots.csv')
    puts "FCT Snapshot Analysis"
    puts "Input: #{input_file}"
    puts "Output: #{output_file}"
    puts "Snapshot interval: #{SNAP} blocks"
    puts "-" * 60
    
    # Read the raw data
    raw_data = CSV.read(input_file, headers: true)
    puts "Loaded #{raw_data.length} blocks"
    
    # Get key boundaries
    fork_block = @fork_block
    head_block = raw_data[-1]['block'].to_i
    
    # Build snapshot blocks list
    snapshot_blocks = build_snapshot_blocks(fork_block, head_block, SNAP)
    puts "Total snapshots: #{snapshot_blocks.length}"
    
    # Create a hash for quick lookup
    block_data_hash = {}
    raw_data.each do |row|
      block_data_hash[row['block'].to_i] = row
    end
    
    # Process snapshots
    snapshots = []
    prev_snapshot = nil
    tolerance_breaches = []
    
    snapshot_blocks.each_with_index do |block_num, idx|
      # Skip if we don't have data for this block
      next unless block_data_hash[block_num]
      
      row = block_data_hash[block_num]
      
      # Basic data
      total_minted = row['total_minted'].to_i
      total_minted_ether = BigDecimal(total_minted) / BigDecimal(10**18)
      mint_rate = row['mint_rate'].to_i
      mint_rate_ether = BigDecimal(mint_rate)
      
      # Calculate theoretical schedule
      blocks_in_first_halving = FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING
      max_supply = FctMintCalculator.max_supply
      schedule_total = (0.5 * max_supply * block_num / blocks_in_first_halving.to_f)
      schedule_total_ether = schedule_total / 1e18
      supply_delta_pct = total_minted > 0 ? ((total_minted.to_f / schedule_total) - 1) * 100 : 0
      
      # Calculate minting since last snapshot
      if prev_snapshot
        minted_since_last = total_minted - prev_snapshot[:total_minted]
        minted_since_last_ether = BigDecimal(minted_since_last) / BigDecimal(10**18)
        blocks_elapsed = block_num - prev_snapshot[:block]
        
        # Calculate expected minting
        snapshot_target = FctMintCalculator.target_per_period / 1e18
        period_length = FctMintCalculator::ADJUSTMENT_PERIOD_TARGET_LENGTH.to_f

        # Calculate expected minting based on the configured adjustment period length
        expected_mint = snapshot_target * (blocks_elapsed / period_length)

        # Guard against division by zero
        if expected_mint.positive?
          pace_delta_pct = minted_since_last_ether > 0 ?
            ((minted_since_last_ether.to_f / expected_mint) - 1) * 100 : -100
        else
          pace_delta_pct = 0
        end
        
        # Rate change factor
        if prev_snapshot[:mint_rate] > 0
          rate_change_factor = mint_rate.to_f / prev_snapshot[:mint_rate]
        else
          rate_change_factor = nil
        end
        
        # Implied burn
        if mint_rate > 0 && minted_since_last > 0
          implied_burn_eth = (minted_since_last.to_f / mint_rate) / 1e18
        else
          implied_burn_eth = 0
        end
      else
        minted_since_last_ether = BigDecimal(0)
        expected_mint = 0
        pace_delta_pct = 0
        rate_change_factor = nil
        implied_burn_eth = 0
      end
      
      # TODO: Get timestamp from block header (requires additional RPC call)
      timestamp = nil
      
      # TODO: Concentration metrics every 10k blocks
      top_1_pct = nil
      top_10_pct = nil
      gini = nil
      
      snapshot = {
        block: block_num,
        timestamp: timestamp,
        total_minted_eth: total_minted_ether.to_f.round(4),
        schedule_total_eth: schedule_total_ether.round(4),
        supply_delta_pct: supply_delta_pct.round(2),
        minted_since_last_eth: minted_since_last_ether.to_f.round(4),
        expected_mint_eth: expected_mint.round(4),
        pace_delta_pct: pace_delta_pct.round(2),
        mint_rate_eth: mint_rate_ether.to_f.round(9),
        rate_change_factor: rate_change_factor ? rate_change_factor.round(3) : nil,
        implied_burn_eth: implied_burn_eth.round(5),
        top_1_pct: top_1_pct,
        top_10_pct: top_10_pct,
        gini: gini,
        total_minted: total_minted,  # Keep raw value for next iteration
        mint_rate: mint_rate          # Keep raw value for next iteration
      }
      
      # Check tolerances
      if prev_snapshot
        # Supply tolerance check
        if supply_delta_pct.abs > (SUPPLY_TOLERANCE * 100)
          if tolerance_breaches.last && tolerance_breaches.last[:type] == :supply &&
             tolerance_breaches.last[:block] == prev_snapshot[:block]
            puts "WARNING: Supply delta exceeds ±#{SUPPLY_TOLERANCE*100}% for 2 consecutive snapshots at block #{block_num}"
          else
            tolerance_breaches << { type: :supply, block: block_num, value: supply_delta_pct }
          end
        end
        
        # Pace tolerance check
        if pace_delta_pct.abs > (PACE_TOLERANCE * 100)
          if tolerance_breaches.last && tolerance_breaches.last[:type] == :pace &&
             tolerance_breaches.last[:block] == prev_snapshot[:block]
            puts "WARNING: Pace delta exceeds ±#{PACE_TOLERANCE*100}% for 2 consecutive snapshots at block #{block_num}"
          else
            tolerance_breaches << { type: :pace, block: block_num, value: pace_delta_pct }
          end
        end
      end
      
      snapshots << snapshot
      prev_snapshot = snapshot
    end
    
    # Write CSV
    CSV.open(output_file, 'w') do |csv|
      headers = ['block', 'timestamp', 'total_minted_eth', 'schedule_total_eth', 'supply_delta_pct',
                 'minted_since_last_eth', 'expected_mint_eth', 'pace_delta_pct',
                 'mint_rate_eth', 'rate_change_factor', 'implied_burn_eth',
                 'top_1_pct', 'top_10_pct', 'gini']
      csv << headers
      
      snapshots.each do |snapshot|
        csv << headers.map { |h| snapshot[h.to_sym] }
      end
    end
    
    # Print summary
    print_snapshot_summary(snapshots, tolerance_breaches)
    
    puts "\nSnapshot analysis complete!"
    puts "Output saved to: #{output_file}"
  end
  
  private
  
  def build_snapshot_blocks(fork_block, head_block, snap_interval)
    blocks = Set.new
    
    # Always include block 0
    blocks << 0
    
    # Include fork block and fork-1
    blocks << fork_block if fork_block > 0
    blocks << (fork_block - 1) if fork_block > 1
    
    # Add regular snapshots
    current = fork_block
    while current <= head_block
      blocks << current
      current += snap_interval
    end
    
    # Add halving boundaries
    blocks_in_halving = FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING
    k = 1
    loop do
      halving_block = fork_block + (k * blocks_in_halving)
      break if halving_block > head_block
      blocks << halving_block
      k += 1
    end
    
    # Always include head block
    blocks << head_block
    
    # Return sorted array
    blocks.to_a.sort.select { |b| b >= fork_block && b <= head_block }
  end
  
  def print_snapshot_summary(snapshots, tolerance_breaches)
    puts "\nSnapshot Analysis Summary:"
    puts "=" * 60
    
    # Basic stats
    puts "Total snapshots: #{snapshots.length}"
    
    if snapshots.any?
      latest = snapshots.last
      puts "\nLatest snapshot (block #{latest[:block]}):"
      puts "- Total minted: #{latest[:total_minted_eth]} FCT"
      puts "- Schedule total: #{latest[:schedule_total_eth]} FCT"
      puts "- Supply delta: #{latest[:supply_delta_pct]}%"
      puts "- Current mint rate: #{latest[:mint_rate_eth]} FCT/gas"
      
      # Average pace delta
      pace_deltas = snapshots[1..-1].map { |s| s[:pace_delta_pct] }.compact
      if pace_deltas.any?
        avg_pace = pace_deltas.sum / pace_deltas.length
        puts "\nAverage pace delta: #{avg_pace.round(2)}%"
      end
      
      # Rate changes
      rate_changes = snapshots.map { |s| s[:rate_change_factor] }.compact
      if rate_changes.any?
        puts "\nRate adjustments: #{rate_changes.length}"
        puts "- 2x increases: #{rate_changes.count { |r| r >= 1.9 }}"
        puts "- 2x decreases: #{rate_changes.count { |r| r <= 0.55 }}"
      end
    end
    
    # Tolerance breaches
    if tolerance_breaches.any?
      puts "\nTOLERANCE BREACHES:"
      supply_breaches = tolerance_breaches.select { |b| b[:type] == :supply }
      pace_breaches = tolerance_breaches.select { |b| b[:type] == :pace }
      
      if supply_breaches.any?
        puts "- Supply tolerance (±#{SUPPLY_TOLERANCE*100}%): #{supply_breaches.length} breaches"
      end
      if pace_breaches.any?
        puts "- Pace tolerance (±#{PACE_TOLERANCE*100}%): #{pace_breaches.length} breaches"
      end
    else
      puts "\nNo tolerance breaches detected ✓"
    end
  end
  
  # Analyze the collected data and create enriched CSVs
  def analyze(input_file: @output_file, output_file: 'tmp/fct_analysis.csv', periods_file: 'tmp/fct_periods.csv')
    puts "FCT Data Analyzer"
    puts "Input: #{input_file}"
    puts "Block analysis output: #{output_file}"
    puts "Period analysis output: #{periods_file}"
    puts "-" * 60
    
    # Read the raw data
    raw_data = CSV.read(input_file, headers: true)
    puts "Loaded #{raw_data.length} blocks"
    
    # Process and analyze
    analyzed_data = []
    periods_data = []
    prev_row = nil
    period_counter = 0
    
    # Track current period data
    current_period = nil
    period_accumulator = BigDecimal(0)
    
    raw_data.each_with_index do |row, idx|
      block_num = row['block'].to_i
      mint_rate = row['mint_rate'].to_i
      total_minted = row['total_minted'].to_i
      period_start = row['period_start_block'].to_i
      period_minted = row['period_minted'].to_i
      
      # Convert to Ether with BigDecimal
      total_minted_ether = (BigDecimal(total_minted) / BigDecimal(10**18))
      period_minted_ether = (BigDecimal(period_minted) / BigDecimal(10**18))
      
      # Calculate per-block minting
      if prev_row
        block_minted = total_minted - prev_row['total_minted'].to_i
        block_minted_ether = (BigDecimal(block_minted) / BigDecimal(10**18))
      else
        block_minted = 0
        block_minted_ether = BigDecimal(0)
      end
      
      # Calculate pace (comparing to theoretical issuance) - moved up
      pace_delta = calculate_pace_delta(block_num, total_minted)
      
      # Detect period change
      period_changed = prev_row && prev_row['period_start_block'].to_i != period_start
      
      if period_changed
        # Finalize previous period
        if current_period
          current_period[:end_block] = prev_row['block'].to_i
          current_period[:num_blocks] = current_period[:end_block] - current_period[:start_block] + 1
          # Use accumulated minting for the period
          current_period[:minted_ether] = period_accumulator.to_f.round(4)
          current_period[:end_pace_delta_pct] = calculate_pace_delta(prev_row['block'].to_i, prev_row['total_minted'].to_i) * 100
          
          # Debug check
          if current_period[:minted_ether] > 150000
            puts "ERROR: Period #{current_period[:period_num]} minted #{current_period[:minted_ether]} FCT (> 150k)"
            puts "  Blocks: #{current_period[:start_block]}-#{current_period[:end_block]} (#{current_period[:num_blocks]} blocks)"
          end
          
          periods_data << current_period
        end
        
        period_counter += 1
        
        # Reset accumulator for new period
        period_accumulator = BigDecimal(0)
        
        # Start new period
        # Calculate rate change from previous period
        period_rate_change = nil
        if periods_data.any? && periods_data.last[:mint_rate] > 0
          period_rate_change = (mint_rate.to_f / periods_data.last[:mint_rate]).round(3)
        end
        
        current_period = {
          period_num: period_counter,
          start_block: period_start,
          mint_rate: mint_rate,
          rate_change_factor: period_rate_change,
          start_pace_delta_pct: (pace_delta * 100).round(2)
        }
      end
      
      # Initialize first period if needed
      if current_period.nil? && period_start > 0
        current_period = {
          period_num: period_counter,
          start_block: period_start,
          mint_rate: mint_rate,
          rate_change_factor: nil,
          start_pace_delta_pct: (pace_delta * 100).round(2)
        }
        # For first period, start fresh
        period_accumulator = BigDecimal(0)
      end
      
      # Calculate blocks into period
      blocks_into_period = block_num - period_start
      
      # Detect rate change
      if prev_row && prev_row['mint_rate'].to_i != mint_rate
        prev_rate = prev_row['mint_rate'].to_i
        if prev_rate > 0
          rate_change_factor = (mint_rate.to_f / prev_rate).round(3)
        else
          rate_change_factor = nil
        end
      else
        rate_change_factor = nil
      end
      
      # Calculate implied L1 data gas (FCT minted = L1_data_gas * mint_rate)
      if mint_rate > 0 && block_minted > 0
        l1_eth_burn = (block_minted.to_f / mint_rate) / 1e18
      else
        l1_eth_burn = 0
      end
      
      analyzed_data << {
        block: block_num,
        mint_rate: mint_rate,
        total_minted_ether: total_minted_ether.to_f.round(4),
        period_start_block: period_start,
        period_minted_ether: period_minted_ether.to_f.round(4),
        block_minted_ether: block_minted_ether.to_f.round(4),
        period_num: period_counter,
        period_changed: period_changed,
        blocks_into_period: blocks_into_period,
        rate_change_factor: rate_change_factor,
        l1_eth_burn: l1_eth_burn.round(5),
        pace_delta_pct: (pace_delta * 100).round(2)
      }
      
      # Accumulate minting for the current period
      # Only accumulate if we have a current period (not before the first period starts)
      if current_period
        period_accumulator += block_minted_ether
        
        # Extra debug for problematic periods
        if period_counter == 13 && block_minted_ether > 0
          puts "DEBUG Period 13: Block #{block_num}, minted #{block_minted_ether.to_f.round(4)}, accumulator now #{period_accumulator.to_f.round(4)}"
        end
      end
      
      prev_row = row
    end
    
    # Finalize last period
    if current_period && prev_row
      current_period[:end_block] = prev_row['block'].to_i
      current_period[:num_blocks] = current_period[:end_block] - current_period[:start_block] + 1
      current_period[:minted_ether] = period_accumulator.to_f.round(4)
      current_period[:end_pace_delta_pct] = calculate_pace_delta(prev_row['block'].to_i, prev_row['total_minted'].to_i) * 100
      periods_data << current_period
    end
    
    # Write block analysis data
    CSV.open(output_file, 'w') do |csv|
      headers = analyzed_data.first.keys
      csv << headers
      
      analyzed_data.each do |row|
        csv << headers.map { |h| row[h] }
      end
    end
    
    # Write periods data
    CSV.open(periods_file, 'w') do |csv|
      headers = ['period_num', 'start_block', 'end_block', 'num_blocks', 'mint_rate', 'minted_ether', 
                 'rate_change_factor', 'start_pace_delta_pct', 'end_pace_delta_pct', 'pace_improvement_pct']
      csv << headers
      
      periods_data.each do |period|
        pace_improvement = period[:end_pace_delta_pct] - period[:start_pace_delta_pct]
        csv << [
          period[:period_num],
          period[:start_block],
          period[:end_block],
          period[:num_blocks],
          period[:mint_rate],
          period[:minted_ether],
          period[:rate_change_factor],
          period[:start_pace_delta_pct].round(2),
          period[:end_pace_delta_pct].round(2),
          pace_improvement.round(2)
        ]
      end
    end
    
    # Print summary
    print_analysis_summary(analyzed_data, periods_data)
    
    puts "\nAnalysis complete!"
    puts "Block analysis saved to: #{output_file}"
    puts "Period analysis saved to: #{periods_file}"
  end
  
  private
  
  def calculate_pace_delta(block_num, total_minted)
    # Use the same calculation as FctMintCalculator.issuance_on_pace_delta
    max_supply = FctMintCalculator.max_supply.to_r
    target_num_blocks_in_halving = FctMintCalculator::TARGET_NUM_BLOCKS_IN_HALVING
    
    supply_target_first_halving = max_supply / 2
    actual_fraction = Rational(total_minted, supply_target_first_halving)
    time_fraction = Rational(block_num) / target_num_blocks_in_halving
    
    return 0 if time_fraction.zero?
    
    ratio = actual_fraction / time_fraction
    (ratio - 1).to_f.round(5)
  end
  
  def calculate_period_target(block_num)
    # Calculate the target for a period starting at block_num
    # This should match FctMintCalculator.target_per_period adjusted for halvings
    base_target = FctMintCalculator.target_per_period
    
    # For now, assume we're in the first halving (no adjustment needed)
    # In reality, we'd need to check total minted at block_num to determine halving level
    (base_target / 1e18).to_f
  end
  
  def print_analysis_summary(data, periods_data)
    puts "\nAnalysis Summary:"
    puts "=" * 60
    
    # Basic stats
    total_blocks = data.length
    total_minted = data.last[:total_minted_ether]
    total_periods = periods_data.length
    
    puts "Total blocks analyzed: #{total_blocks}"
    puts "Total FCT minted: #{total_minted.round(2)} FCT"
    puts "Total periods: #{total_periods}"
    
    # Rate changes
    rate_changes = data.select { |d| d[:rate_change_factor] }
    if rate_changes.any?
      puts "\nRate changes: #{rate_changes.length}"
      puts "- 2x increases: #{rate_changes.count { |d| d[:rate_change_factor] >= 1.9 }}"
      puts "- 2x decreases: #{rate_changes.count { |d| d[:rate_change_factor] <= 0.55 }}"
    end
    
    # Pace analysis
    pace_deltas = data.map { |d| d[:pace_delta_pct] }.compact
    avg_pace = pace_deltas.sum / pace_deltas.length
    
    puts "\nPace analysis:"
    puts "- Average pace delta: #{avg_pace.round(2)}%"
    puts "- Current pace delta: #{data.last[:pace_delta_pct]}%"
    
    # Minting stats
    non_zero_blocks = data.select { |d| d[:block_minted_ether] > 0 }
    if non_zero_blocks.any?
      avg_mint_per_block = non_zero_blocks.sum { |d| d[:block_minted_ether] } / non_zero_blocks.length
      puts "\nMinting stats:"
      puts "- Blocks with minting: #{non_zero_blocks.length} (#{(non_zero_blocks.length * 100.0 / total_blocks).round(1)}%)"
      puts "- Average FCT per minting block: #{avg_mint_per_block.round(4)}"
    end
    
    # Period stats
    if periods_data.any?
      avg_period_length = periods_data.sum { |p| p[:num_blocks] } / periods_data.length.to_f
      early_periods = periods_data.select { |p| p[:num_blocks] < 1000 }
      
      puts "\nPeriod stats:"
      puts "- Average period length: #{avg_period_length.round(1)} blocks"
      puts "- Periods ending early: #{early_periods.length} (#{(early_periods.length * 100.0 / periods_data.length).round(1)}%)"
      
      # Rate change distribution
      rate_ups = periods_data.select { |p| p[:rate_change_factor] && p[:rate_change_factor] > 1.1 }
      rate_downs = periods_data.select { |p| p[:rate_change_factor] && p[:rate_change_factor] < 0.9 }
      
      puts "- Periods with rate increase: #{rate_ups.length}"
      puts "- Periods with rate decrease: #{rate_downs.length}"
    end
  end
end