class ScheduledPayment::RobustEstimator
  MAD_SCALE = BigDecimal("1.4826")
  WINSOR_MULTIPLIER = BigDecimal("2.5")

  Result = Data.define(:central, :spread, :lower, :upper)

  def self.call(values, decay:)
    new(values, decay:).call
  end

  def initialize(values, decay:)
    @values = values.map { |value| BigDecimal(value.to_s) }
    @decay = BigDecimal(decay.to_s)
  end

  def call
    return Result.new(central: 0.to_d, spread: 0.to_d, lower: 0.to_d, upper: 0.to_d) if values.empty?

    center = median(values)
    deviations = values.map { |value| (value - center).abs }
    mad = median(deviations)
    spread = robust_spread(mad)
    lower, upper = winsor_bounds(center, mad, spread)
    clamped = values.map { |value| value.clamp(lower, upper) }
    weights = clamped.each_index.map { |index| decay**(clamped.size - index - 1) }
    central = clamped.zip(weights).sum { |value, weight| value * weight } / weights.sum

    Result.new(central:, spread:, lower:, upper:)
  end

  private

    attr_reader :values, :decay

    def robust_spread(mad)
      return mad * MAD_SCALE unless mad.zero?
      return 0.to_d if values.uniq.one?

      # With a zero MAD, repeated central observations can otherwise leave a
      # genuine tail completely unbounded. IQR is the first fallback; the
      # central 80% range handles small samples where both quartiles coincide.
      iqr = percentile(values, BigDecimal("0.75")) - percentile(values, BigDecimal("0.25"))
      return iqr / BigDecimal("1.349") if iqr.positive?

      robust_range = percentile(values, BigDecimal("0.90")) - percentile(values, BigDecimal("0.10"))
      return robust_range / BigDecimal("2.563") if robust_range.positive?

      (values.max - values.min).abs / 2
    end

    def winsor_bounds(center, mad, spread)
      width = mad.positive? ? mad * WINSOR_MULTIPLIER : spread * WINSOR_MULTIPLIER
      [ center - width, center + width ]
    end

    def median(collection)
      percentile(collection, BigDecimal("0.5"))
    end

    def percentile(collection, percentile)
      sorted = collection.sort
      position = percentile * (sorted.length - 1)
      lower_index = position.floor
      upper_index = position.ceil
      return sorted[lower_index] if lower_index == upper_index

      fraction = position - lower_index
      sorted[lower_index] + (sorted[upper_index] - sorted[lower_index]) * fraction
    end
end
