class ScheduledPayment::Forecast
  HORIZONS = [ 1, 3, 6, 12, 36 ].freeze
  HISTORY_MONTHS = 12
  ESTIMATE_VARIANCE = ScheduledPayment::EstimateUncertainty::FALLBACK
  Scenario = Data.define(:key, :monthly_residual)
  Event = Data.define(:date, :delta, :estimated, :uncertainty)

  attr_reader :family, :user, :account, :horizon_months, :conversion_failures

  def initialize(family:, user:, account:, horizon_months: 3)
    @family = family
    @user = user
    @account = account
    @horizon_months = HORIZONS.include?(horizon_months.to_i) ? horizon_months.to_i : 3
    @conversion_failures = 0
  end

  def start_date
    Date.current
  end

  def end_date
    start_date >> horizon_months
  end

  def history_months
    historical_monthly_changes.size
  end

  def current_balance
    Money.new(account.balance, account.currency)
  end

  def historical_monthly_savings
    Money.new(central_monthly_change, account.currency)
  end

  def irregular_reserve
    Money.new(irregular_monthly_reserve, account.currency)
  end

  def scheduled_monthly_change
    total = future_events.sum(&:delta) / BigDecimal(horizon_months.to_s)
    Money.new(total, account.currency)
  end

  def projected_monthly_savings
    change = ending_balance(:normal).amount - current_balance.amount
    Money.new(change / BigDecimal(horizon_months.to_s), account.currency)
  end

  def scheduled_event_count
    future_events.size
  end

  def ignored_one_time_count
    @ignored_one_time_count ||= historical_scope
      .where(date: completed_periods.first.begin..completed_periods.last.end, transactions: { kind: "one_time" }).count
  end

  def ending_balance(scenario)
    point = chart_data.fetch(:points).last
    Money.new(point.fetch(scenario).fetch(:amount), account.currency)
  end

  def chart_data
    @chart_data ||= {
      points: projection_dates.map { |date| projection_point(date) },
      scenario_labels: {
        pessimistic: I18n.t("scheduled_payments.agenda.forecast.scenarios.pessimistic"),
        normal: I18n.t("scheduled_payments.agenda.forecast.scenarios.normal"),
        optimistic: I18n.t("scheduled_payments.agenda.forecast.scenarios.optimistic")
      }
    }
  end

  private

    def completed_periods
      @completed_periods ||= begin
        last_day = family.custom_month_start_for(start_date) - 1.day
        HISTORY_MONTHS.times.map do
          period_end = family.custom_month_end_for(last_day)
          period_start = family.custom_month_start_for(last_day)
          last_day = period_start - 1.day
          period_start..period_end
        end.reverse
      end
    end

    def eligible_historical_entries
      linked_ids = ScheduledPaymentEntry.where.not(entry_id: nil).select(:entry_id)
      historical_scope.where.not(id: linked_ids)
        .where.not(transactions: { kind: Transaction::TRANSFER_KINDS + [ "one_time" ] })
    end

    def historical_scope
      @historical_scope ||= account.entries
        .where(entryable_type: "Transaction", excluded: false)
        .excluding_pending
        .excluding_split_parents
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
    end

    def historical_monthly_changes
      @historical_monthly_changes ||= begin
        periods = completed_periods
        entries = eligible_historical_entries.where(date: periods.first.begin..periods.last.end).to_a
          .reject { |entry| explained_by_schedule?(entry) || entry.entryable.forecast_irregular_recurring? }
        first_activity = entries.map(&:date).min
        applicable = first_activity ? periods.drop_while { |period| period.end < first_activity } : []

        applicable.map do |period|
          -entries.select { |entry| period.cover?(entry.date) }.sum(&:amount)
        end
      end
    end

    def irregular_monthly_reserve
      @irregular_monthly_reserve ||= begin
        periods = completed_periods
        entries = historical_scope.where(
          date: periods.first.begin..periods.last.end,
          transactions: { forecast_behavior: "irregular_recurring" }
        ).to_a.reject { |entry| explained_by_schedule?(entry) }
        first_activity = historical_scope.where(date: periods.first.begin..periods.last.end).minimum(:date)
        observed = first_activity ? periods.drop_while { |period| period.end < first_activity } : []
        observed.empty? ? 0.to_d : -entries.sum(&:amount) / BigDecimal(observed.size.to_s)
      end
    end

    def explained_by_schedule?(entry)
      matching_payments.any? do |payment|
        next false unless payment.title.to_s.squish.casecmp?(entry.name.to_s.squish)
        next false unless payment.expense? == entry.amount.positive?

        tolerance = payment.amount_estimated? ? BigDecimal("0.35") : BigDecimal("0.10")
        amount_matches = (entry.amount.abs - payment.amount).abs <= payment.amount * tolerance
        amount_matches && payment.occurrences_in((entry.date - 5.days)..(entry.date + 5.days)).any?
      end
    end

    def matching_payments
      @matching_payments ||= family.scheduled_payments.accessible_by(user)
        .where(account_id: account.id, payment_type: %w[expense income]).to_a
    end

    def central_monthly_change
      robust_history.central
    end

    def robust_history
      @robust_history ||= ScheduledPayment::RobustEstimator.call(historical_monthly_changes, decay: BigDecimal("0.92"))
    end

    def scenarios
      @scenarios ||= [
        Scenario.new(key: :pessimistic, monthly_residual: central_monthly_change - robust_history.spread),
        Scenario.new(key: :normal, monthly_residual: central_monthly_change),
        Scenario.new(key: :optimistic, monthly_residual: central_monthly_change + robust_history.spread)
      ]
    end

    def future_events
      @future_events ||= begin
        range = (start_date + 1.day)..end_date
        payments = family.scheduled_payments.accessible_by(user)
          .where("account_id = :id OR target_account_id = :id", id: account.id)
          .to_a
        stored = ScheduledPaymentEntry.where(scheduled_payment_id: payments.map(&:id), scheduled_date: range)
          .includes(:entry, :transfer_entry).to_a.group_by(&:scheduled_payment_id)

        payments.flat_map do |payment|
          records = stored.fetch(payment.id, []).index_by(&:scheduled_date)
          dates = payment.active? ? payment.occurrences_in(range) : []
          (dates | records.keys).filter_map do |date|
            record = records[date]
            next if record&.skipped? || record&.rejected?

            build_event(payment, date, record)
          end
        end.sort_by(&:date)
      end
    end

    def build_event(payment, date, record)
      if record&.confirmed?
        entry = payment.account_id == account.id ? record.entry : record.transfer_entry
        return unless entry
        return if entry.date <= start_date

        return Event.new(date: entry.date, delta: -entry.amount, estimated: false, uncertainty: 0.to_d)
      end

      delta = if payment.account_id == account.id
        payment.income? ? payment.amount : -payment.amount
      else
        converted_transfer_amount(payment)
      end
      Event.new(
        date:, delta:, estimated: payment.amount_estimated?,
        uncertainty: ScheduledPayment::EstimateUncertainty.for(payment, before: start_date)
      ) if delta
    end

    def converted_transfer_amount(payment)
      Money.new(payment.amount, payment.currency).exchange_to(account.currency, date: start_date).amount
    rescue Money::ConversionError
      @conversion_failures += 1
      nil
    end

    def projection_dates
      @projection_dates ||= ([ start_date, end_date ] +
        (start_date..end_date).step(7).to_a +
        future_events.flat_map { |event| [ event.date - 1.day, event.date ] })
        .select { |date| (start_date..end_date).cover?(date) }.uniq.sort
    end

    def projection_point(date)
      elapsed_months = BigDecimal((date - start_date).to_i.to_s) / BigDecimal("30.4375")
      scenarios.each_with_object({ date: date.iso8601, label: I18n.l(date, format: :short) }) do |scenario, point|
        scheduled_delta = future_events.select { |event| event.date <= date }.sum do |event|
          event.delta * estimated_multiplier(event, scenario.key)
        end
        amount = BigDecimal(account.balance.to_s) +
          (scenario.monthly_residual + irregular_monthly_reserve) * elapsed_months + scheduled_delta
        money = Money.new(amount, account.currency)
        point[scenario.key] = { amount: amount.to_f, formatted: money.format }
      end
    end

    def estimated_multiplier(event, scenario)
      return BigDecimal("1") unless event.estimated
      return BigDecimal("1") if scenario == :normal

      adverse = event.delta.negative? ? BigDecimal("1") + event.uncertainty : BigDecimal("1") - event.uncertainty
      scenario == :pessimistic ? adverse : BigDecimal("2") - adverse
    end
end
