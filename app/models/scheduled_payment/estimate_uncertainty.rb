class ScheduledPayment::EstimateUncertainty
  MINIMUM_OBSERVATIONS = 4
  FALLBACK = BigDecimal("0.15")
  MAXIMUM = BigDecimal("1")

  def self.for(payment, before:)
    new(payment, before:).value
  end

  def initialize(payment, before:)
    @payment = payment
    @before = before
  end

  def value
    return FALLBACK unless payment.amount_estimated?
    return FALLBACK if relative_errors.size < MINIMUM_OBSERVATIONS

    result = ScheduledPayment::RobustEstimator.call(relative_errors, decay: 1)
    result.spread.clamp(0.to_d, MAXIMUM)
  end

  private

    attr_reader :payment, :before

    def relative_errors
      @relative_errors ||= payment.scheduled_payment_entries.confirmed
        .where("scheduled_date < ?", before)
        .includes(:entry, :transfer_entry)
        .filter_map do |occurrence|
          actual = actual_amount(occurrence)
          next if actual.nil? || payment.amount.zero?

          (actual - payment.amount) / payment.amount
        end
    end

    def actual_amount(occurrence)
      entry = occurrence.entry
      return unless entry

      Money.new(entry.amount.abs, entry.currency)
        .exchange_to(payment.currency, date: entry.date).amount
    rescue Money::ConversionError
      nil
    end
end
