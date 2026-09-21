class ScheduledPayment::ForecastBacktest
  HORIZONS = [ 3, 6, 12 ].freeze
  Result = Data.define(:model, :horizon_months, :samples, :bias, :mae, :coverage)

  attr_reader :family, :user, :cutoffs, :cashflow_scenario_z

  def initialize(family:, user:, cutoffs: nil,
                 cashflow_scenario_z: ScheduledPayment::WealthForecast::CASHFLOW_SCENARIO_Z)
    @family = family
    @user = user
    @cutoffs = cutoffs || default_cutoffs
    @cashflow_scenario_z = BigDecimal(cashflow_scenario_z.to_s)
    unless @cashflow_scenario_z.finite? && @cashflow_scenario_z >= 0
      raise ArgumentError, "cashflow_scenario_z must be a finite non-negative number"
    end
  end

  def call
    HORIZONS.flat_map do |horizon|
      observations = cutoffs.filter_map { |cutoff| observation(cutoff, horizon) }
      [ summarize(:v2, horizon, observations), summarize(:v1, horizon, observations) ]
    end
  end

  def limitation
    "Agenda definitions are not historically versioned, so both models omit Agenda during backtesting. " \
      "Only dated balances, transactions and market-flow rows on or before each cutoff fit V2; historical versions " \
      "of account visibility and transaction classifications cannot be reconstructed."
  end

  private

    def default_cutoffs
      latest_target = Date.current << HORIZONS.max
      24.times.map { |index| family.custom_month_start_for(latest_target << index) - 1.day }.reverse
    end

    def observation(cutoff, horizon)
      target = cutoff >> horizon
      forecast = ScheduledPayment::WealthForecast.new(
        family:, user:, horizon_months: horizon, as_of: cutoff, include_agenda: false,
        cashflow_scenario_z:
      )
      actual = forecast.balance_at(target)
      return if actual.zero? && forecast.balance_at(target - 1.day).zero?

      v2 = prediction_from(forecast)
      v1 = legacy_prediction(cutoff, horizon, forecast.current_balance.amount)
      { actual:, v2:, v1: }
    end

    def prediction_from(forecast)
      {
        normal: forecast.ending_balance(:normal).amount,
        lower: forecast.ending_balance(:pessimistic).amount,
        upper: forecast.ending_balance(:optimistic).amount
      }
    end

    def legacy_prediction(cutoff, horizon, current)
      accounts = family.accounts.historical.included_in_reports.included_in_finances_for(user).assets
      month_ends = 61.times.map { |index| family.custom_month_start_for(cutoff << index) - 1.day }.reverse
      values = month_ends.filter_map do |date|
        rows = accounts.filter_map { |account| account.balances.where("date <= ?", date).order(date: :desc).first }
        next if rows.empty?
        rows.sum { |row| Money.new(row.balance, row.currency).exchange_to(family.currency, date: row.date).amount }
      rescue Money::ConversionError
        nil
      end
      changes = values.each_cons(2).map { |previous, following| following - previous }
      stats = ScheduledPayment::RobustEstimator.call(changes, decay: BigDecimal("0.97"))
      months = BigDecimal(horizon.to_s)
      {
        normal: current + stats.central * months,
        lower: current + (stats.central - stats.spread) * months,
        upper: current + (stats.central + stats.spread) * months
      }
    end

    def summarize(model, horizon, observations)
      errors = observations.map { |item| item[:actual] - item.fetch(model).fetch(:normal) }
      covered = observations.count do |item|
        prediction = item.fetch(model)
        item[:actual].between?(*[ prediction[:lower], prediction[:upper] ].minmax)
      end
      count = observations.size
      Result.new(
        model:, horizon_months: horizon, samples: count,
        bias: count.zero? ? nil : errors.sum / count,
        mae: count.zero? ? nil : errors.sum(&:abs) / count,
        coverage: count.zero? ? nil : BigDecimal(covered.to_s) / count
      )
    end
end
