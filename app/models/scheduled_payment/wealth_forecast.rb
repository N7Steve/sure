class ScheduledPayment::WealthForecast
  HORIZONS = ScheduledPayment::Forecast::HORIZONS
  HISTORY_MONTHS = 60
  ESTIMATE_VARIANCE = ScheduledPayment::Forecast::ESTIMATE_VARIANCE
  RECENCY_DECAY = BigDecimal("0.97")

  Scenario = Data.define(:key, :monthly_residual)
  Event = Data.define(:date, :delta, :estimated)

  attr_reader :family, :user, :horizon_months, :conversion_failures

  def initialize(family:, user:, horizon_months: 3)
    @family = family
    @user = user
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
    @current_balance ||= Money.new(current_asset_accounts.sum { |account| converted_account_balance(account) }, currency)
  end

  def historical_monthly_savings
    Money.new(central_monthly_change, currency)
  end

  def scheduled_monthly_change
    total = future_events.sum(&:delta) / BigDecimal(horizon_months.to_s)
    Money.new(total, currency)
  end

  def projected_monthly_savings
    change = ending_balance(:normal).amount - current_balance.amount
    Money.new(change / BigDecimal(horizon_months.to_s), currency)
  end

  def scheduled_event_count
    future_events.size
  end

  def ignored_one_time_count
    one_time_entries.size
  end

  def ending_balance(scenario)
    point = chart_data.fetch(:points).last
    Money.new(point.fetch(scenario).fetch(:amount), currency)
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

    def currency
      family.currency
    end

    def historical_asset_accounts
      @historical_asset_accounts ||= family.accounts.historical.included_in_reports
        .included_in_finances_for(user).assets.to_a
    end

    def historical_asset_ids
      @historical_asset_ids ||= historical_asset_accounts.map(&:id)
    end

    def current_asset_ids
      @current_asset_ids ||= current_asset_accounts.map(&:id).to_set
    end

    def current_asset_accounts
      @current_asset_accounts ||= family.accounts.visible.included_in_reports
        .included_in_finances_for(user).assets.to_a
    end

    def converted_account_balance(account)
      Money.new(account.balance, account.currency).exchange_to(currency, date: start_date).amount
    rescue Money::ConversionError
      @conversion_failures += 1
      BigDecimal("0")
    end

    def historical_series
      @historical_series ||= begin
        period = Period.custom(
          start_date: family.custom_month_start_for(start_date << HISTORY_MONTHS) - 1.day,
          end_date: family.custom_month_start_for(start_date) - 1.day
        )
        active_until_dates = historical_asset_accounts.each_with_object({}) do |account, dates|
          next unless account.disabled?

          dates[account.id] = (account.disabled_at || account.updated_at).to_date - 1.day
        end
        Balance::ChartSeriesBuilder.new(
          account_ids: historical_asset_ids,
          account_active_until_dates: active_until_dates,
          currency: currency,
          period: period,
          interval: "1 month",
          favorable_direction: "up"
        ).balance_series
      end
    end

    def first_balance_date
      @first_balance_date ||= Balance.where(account_id: historical_asset_ids).minimum(:date)
    end

    def historical_monthly_changes
      @historical_monthly_changes ||= historical_series.values.each_cons(2).filter_map do |previous, current|
        next if first_balance_date.nil? || current.date < first_balance_date

        range = (previous.date + 1.day)..current.date
        raw_change = BigDecimal(current.value.amount.to_s) - BigDecimal(previous.value.amount.to_s)
        scheduled_change = historical_entries_in(range).select { |entry| explained_by_schedule?(entry) }
          .sum { |entry| entry_delta(entry) }
        exceptional_change = historical_entries_in(range).select do |entry|
          entry.entryable.kind == "one_time" && !explained_by_schedule?(entry)
        end.sum { |entry| entry_delta(entry) }

        raw_change - scheduled_change - exceptional_change
      end
    end

    def historical_entries
      @historical_entries ||= begin
        range = historical_series.start_date..historical_series.end_date
        Entry.where(account_id: historical_asset_ids, entryable_type: "Transaction", excluded: false, date: range)
          .excluding_pending
          .excluding_split_parents
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
          .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
          .includes(:entryable)
          .to_a
      end
    end

    def historical_entries_in(range)
      historical_entries.select { |entry| range.cover?(entry.date) }
    end

    def one_time_entries
      @one_time_entries ||= historical_entries.select { |entry| entry.entryable.kind == "one_time" }
    end

    def linked_entry_ids
      @linked_entry_ids ||= ScheduledPaymentEntry.where(scheduled_payment_id: accessible_payments.map(&:id))
        .where.not(entry_id: nil).pluck(:entry_id).to_set
    end

    def explained_by_schedule?(entry)
      @schedule_explanations ||= {}
      @schedule_explanations.fetch(entry.id) do
        @schedule_explanations[entry.id] = linked_entry_ids.include?(entry.id) ||
          matching_payments_by_account.fetch(entry.account_id, []).any? do |payment|
            next false unless payment.title.to_s.squish.casecmp?(entry.name.to_s.squish)
            next false unless payment.expense? == entry.amount.positive?
            next false unless payment.currency == entry.currency

            tolerance = payment.amount_estimated? ? BigDecimal("0.35") : BigDecimal("0.10")
            amount_matches = (entry.amount.abs - payment.amount).abs <= payment.amount * tolerance
            amount_matches && payment.occurrences_in((entry.date - 5.days)..(entry.date + 5.days)).any?
          end
      end
    end

    def matching_payments_by_account
      @matching_payments_by_account ||= accessible_payments.select do |payment|
        payment.account_id.in?(historical_asset_ids) && payment.payment_type.in?(%w[expense income])
      end.group_by(&:account_id)
    end

    def accessible_payments
      @accessible_payments ||= family.scheduled_payments.accessible_by(user).to_a
    end

    def entry_delta(entry)
      Money.new(-entry.amount, entry.currency).exchange_to(currency, date: entry.date).amount
    rescue Money::ConversionError
      @conversion_failures += 1
      BigDecimal("0")
    end

    def central_monthly_change
      robust_history.fetch(:central)
    end

    def robust_history
      @robust_history ||= begin
        values = historical_monthly_changes.map { |value| BigDecimal(value.to_s) }
        if values.empty?
          { central: BigDecimal("0"), spread: BigDecimal("0") }
        else
          median = median(values)
          mad = median(values.map { |value| (value - median).abs })
          clamped = if mad.zero?
            values
          else
            lower = median - mad * BigDecimal("2.5")
            upper = median + mad * BigDecimal("2.5")
            values.map { |value| value.clamp(lower, upper) }
          end
          weights = clamped.each_index.map { |index| RECENCY_DECAY**(clamped.size - index - 1) }
          central = clamped.zip(weights).sum { |value, weight| value * weight } / weights.sum
          spread = mad * BigDecimal("1.4826")
          { central: central, spread: spread }
        end
      end
    end

    def median(values)
      sorted = values.sort
      middle = sorted.length / 2
      sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    end

    def scenarios
      @scenarios ||= [
        Scenario.new(key: :pessimistic, monthly_residual: central_monthly_change - robust_history.fetch(:spread)),
        Scenario.new(key: :normal, monthly_residual: central_monthly_change),
        Scenario.new(key: :optimistic, monthly_residual: central_monthly_change + robust_history.fetch(:spread))
      ]
    end

    def future_events
      @future_events ||= begin
        range = (start_date + 1.day)..end_date
        payments = accessible_payments
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
        entries = [ record.entry, record.transfer_entry ].compact.select do |entry|
          current_asset_ids.include?(entry.account_id) && entry.date > start_date
        end
        return if entries.empty?

        delta = entries.sum { |entry| entry_delta(entry) }
        return if delta.zero?

        return Event.new(date: entries.map(&:date).max, delta: delta, estimated: false)
      end

      delta = if payment.transfer?
        transfer_delta(payment)
      elsif current_asset_ids.include?(payment.account_id)
        payment.income? ? converted_amount(payment) : -converted_amount(payment)
      end
      Event.new(date: date, delta: delta, estimated: payment.amount_estimated?) if delta && !delta.zero?
    end

    def transfer_delta(payment)
      source_included = current_asset_ids.include?(payment.account_id)
      target_included = current_asset_ids.include?(payment.target_account_id)
      return BigDecimal("0") if source_included == target_included

      amount = converted_amount(payment)
      source_included ? -amount : amount
    end

    def converted_amount(payment)
      Money.new(payment.amount, payment.currency).exchange_to(currency, date: start_date).amount
    rescue Money::ConversionError
      @conversion_failures += 1
      BigDecimal("0")
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
        amount = current_balance.amount + scenario.monthly_residual * elapsed_months + scheduled_delta
        money = Money.new(amount, currency)
        point[scenario.key] = { amount: amount.to_f, formatted: money.format }
      end
    end

    def estimated_multiplier(event, scenario)
      return BigDecimal("1") unless event.estimated
      return BigDecimal("1") if scenario == :normal

      adverse = event.delta.negative? ? BigDecimal("1") + ESTIMATE_VARIANCE : BigDecimal("1") - ESTIMATE_VARIANCE
      scenario == :pessimistic ? adverse : BigDecimal("2") - adverse
    end
end
