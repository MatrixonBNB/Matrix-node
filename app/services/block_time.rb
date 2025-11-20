module BlockTime
  TARGET_INTERVAL_SECONDS = 1
  MAX_FUTURE_DRIFT_SECONDS = 2

  module_function

  def interval_seconds
    TARGET_INTERVAL_SECONDS
  end

  def next_after(parent_timestamp, proposed_timestamp: nil, drift_allowance: MAX_FUTURE_DRIFT_SECONDS, now: Time.current)
    raise ArgumentError, "parent_timestamp is required" if parent_timestamp.nil?

    candidate = (proposed_timestamp || parent_timestamp + TARGET_INTERVAL_SECONDS).to_i
    min_timestamp = parent_timestamp + 1
    candidate = [candidate, min_timestamp].max

    max_timestamp = now.to_i + drift_allowance
    max_timestamp = min_timestamp if max_timestamp < min_timestamp

    [candidate, max_timestamp].min
  end
end