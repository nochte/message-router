module Util
  def summarize_history status_history
    keys = status_history.map{|hsh| hsh.keys}.flatten.uniq
    status_history.inject({}) do |result, item|
      keys.each do |key|
        next unless (item.key?(key) && item[key].is_a?(Numeric))
        #((previous average * previous count) + new value) / new count
        # = (previous_sum + new_value) / new_count
        result[key] ||= 0.0
        result["#{key}_count"] ||= 0

        previous_sum = result[key] * result["#{key}_count"]
        result["#{key}_count"] += 1
        result[key] = (previous_sum + item[key]) / result["#{key}_count"]
      end
      result
    end
  end
end