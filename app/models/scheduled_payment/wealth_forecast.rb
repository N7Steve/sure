class ScheduledPayment::WealthForecast
  HORIZONS = ScheduledPayment::Forecast::HORIZONS
  CASHFLOW_HISTORY_MONTHS = 18
  INVESTMENT_HISTORY_MONTHS = 36
  IRREGULAR_HISTORY_MONTHS = 12
  CASHFLOW_DECAY = BigDecimal("0.92")
  INVESTMENT_DECAY = BigDecimal("0.97")
  DAYS_PER_MONTH = BigDecimal("30.4375")

  Scenario = Data.define(:key, :monthly_cashflow)
  Event = Data.define(:date, :delta, :estimated, :uncertainty, :investment_delta)

  attr_reader :family, :user, :horizon_months, :conversion_failures, :as_of

  def initialize(family:, user:, horizon_months: 3, as_of: Date.current, include_agenda: true)
    @family = family
    @user = user
    @horizon_months = HORIZONS.include?(horizon_months.to_i) ? horizon_months.to_i : 3
    @as_of = as_of.to_date
    @include_agenda = include_agenda
    @conversion_failures = 0
  end

  def start_date = as_of
  def end_date = start_date >> horizon_months
  def history_months = historical_monthly_cashflows.size

  def current_balance
    @current_balance ||= Money.new(balance_at(start_date), currency)
  end

  def current_investment_balance
    @current_investment_balance ||= Money.new(accounts_balance_at(current_investment_accounts, start_date), currency)
  end

  def cashflow_residual = Money.new(cashflow_statistics.central, currency)
  def historical_monthly_savings = cashflow_residual
  def irregular_reserve = Money.new(irregular_monthly_reserve, currency)
  def expected_investment_return = Math.expm1(investment_statistics.central.to_f)

  def expected_investment_return_equivalent
    Money.new(current_investment_balance.amount * BigDecimal(expected_investment_return.to_s), currency)
  end

  def scheduled_monthly_change
    Money.new(future_events.sum(&:delta) / BigDecimal(horizon_months.to_s), currency)
  end

  def projected_monthly_savings
    Money.new((ending_balance(:normal).amount - current_balance.amount) / BigDecimal(horizon_months.to_s), currency)
  end

  def scheduled_event_count = future_events.count { |event| !event.delta.zero? }
  def ignored_one_time_count = exceptional_entries.size
  def irregular_entry_count = irregular_entries.size

  def ending_balance(scenario)
    Money.new(chart_data.fetch(:points).last.fetch(scenario).fetch(:amount), currency)
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

  def balance_at(date)
    accounts = date == Date.current ? current_asset_accounts : historical_asset_accounts
    accounts_balance_at(accounts, date)
  end

  private

    attr_reader :include_agenda

    def currency = family.currency

    def historical_asset_accounts
      @historical_asset_accounts ||= family.accounts.historical.included_in_reports
        .included_in_finances_for(user).assets.to_a
    end

    def current_asset_accounts
      @current_asset_accounts ||= family.accounts.visible.included_in_reports
        .included_in_finances_for(user).assets.to_a
    end

    def historical_asset_ids = historical_asset_accounts.map(&:id)
    def current_asset_ids = @current_asset_ids ||= current_asset_accounts.map(&:id).to_set

    def historical_investment_accounts
      @historical_investment_accounts ||= historical_asset_accounts.select { |account| account.investment? || account.crypto? }
    end

    def current_investment_accounts
      @current_investment_accounts ||= begin
        accounts = start_date == Date.current ? current_asset_accounts : historical_asset_accounts
        accounts.select { |account| account.investment? || account.crypto? }
      end
    end

    def current_investment_ids = @current_investment_ids ||= current_investment_accounts.map(&:id).to_set

    def accounts_balance_at(accounts, date)
      return accounts.sum { |account| convert(account.balance, account.currency, date) } if date == Date.current

      accounts.sum do |account|
        balance = account.balances.where("date <= ?", date).order(date: :desc).first
        balance ? convert(balance.balance, balance.currency, balance.date) : 0.to_d
      end
    end

    def cashflow_periods = @cashflow_periods ||= completed_periods(CASHFLOW_HISTORY_MONTHS)
    def investment_periods = @investment_periods ||= completed_periods(INVESTMENT_HISTORY_MONTHS)

    def completed_periods(count)
      last_day = family.custom_month_start_for(start_date) - 1.day
      count.times.map do
        period_end = family.custom_month_end_for(last_day)
        period_start = family.custom_month_start_for(last_day)
        last_day = period_start - 1.day
        period_start..period_end
      end.reverse
    end

    def historical_monthly_cashflows
      @historical_monthly_cashflows ||= begin
        first_activity = historical_entries.map(&:date).min
        applicable = first_activity ? cashflow_periods.drop_while { |period| period.end < first_activity } : []
        applicable.map do |period|
          ordinary_cashflow_entries.select { |entry| period.cover?(entry.date) }.sum { |entry| economic_delta(entry) }
        end
      end
    end

    alias_method :historical_monthly_changes, :historical_monthly_cashflows

    def cashflow_statistics
      @cashflow_statistics ||= ScheduledPayment::RobustEstimator.call(historical_monthly_changes, decay: CASHFLOW_DECAY)
    end

    def historical_entries
      @historical_entries ||= begin
        range = cashflow_periods.first.begin..cashflow_periods.last.end
        Entry.where(account_id: historical_asset_ids, entryable_type: "Transaction", excluded: false, date: range)
          .excluding_pending.excluding_split_parents
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
          .includes(entryable: [ :transfer_as_inflow, :transfer_as_outflow ]).to_a
      end
    end

    def ordinary_cashflow_entries
      historical_entries.reject do |entry|
        explained_by_schedule?(entry) || entry.entryable.forecast_exceptional_once? ||
          entry.entryable.forecast_irregular_recurring? || internal_transfer?(entry)
      end
    end

    def exceptional_entries
      @exceptional_entries ||= historical_entries.select { |entry| entry.entryable.forecast_exceptional_once? }
    end

    def irregular_entries
      @irregular_entries ||= historical_entries.select do |entry|
        entry.entryable.forecast_irregular_recurring? && !explained_by_schedule?(entry) && !internal_transfer?(entry)
      end
    end

    def irregular_monthly_reserve
      return 0.to_d if irregular_entries.empty?

      periods = cashflow_periods.last(IRREGULAR_HISTORY_MONTHS)
      first_data = historical_entries.map(&:date).min
      observed = first_data ? periods.drop_while { |period| period.end < first_data } : []
      return 0.to_d if observed.empty?

      total = irregular_entries.select { |entry| observed.any? { |period| period.cover?(entry.date) } }
        .sum { |entry| economic_delta(entry) }
      total / BigDecimal(observed.size.to_s)
    end

    def internal_transfer?(entry)
      transfer = entry.entryable.transfer
      transfer && historical_asset_ids.include?(transfer.from_account&.id) && historical_asset_ids.include?(transfer.to_account&.id)
    end

    def economic_delta(entry) = convert(-entry.amount, entry.currency, entry.date)

    def investment_monthly_log_returns
      @investment_monthly_log_returns ||= investment_periods.filter_map do |period|
        rows = investment_balance_rows.select { |balance| period.cover?(balance.date) }
        next if rows.empty?

        market_pnl = rows.sum { |balance| convert(balance.net_market_flows, balance.currency, balance.date) }
        opening = rows.group_by(&:account_id).sum do |_account_id, account_rows|
          first = account_rows.min_by(&:date)
          convert(first.start_balance, first.currency, first.date)
        end
        weighted_flows = rows.sum do |balance|
          flow = balance.flows_factor * (
            balance.cash_inflows - balance.cash_outflows + balance.non_cash_inflows - balance.non_cash_outflows
          )
          weight = BigDecimal(((period.end - balance.date).to_i + 1).to_s) / BigDecimal(period.count.to_s)
          convert(flow, balance.currency, balance.date) * weight
        end
        exposed_capital = opening + weighted_flows
        next unless exposed_capital.positive?

        monthly_return = market_pnl / exposed_capital
        next if monthly_return <= -1

        BigDecimal(Math.log1p(monthly_return.to_f).to_s)
      end
    end

    def investment_balance_rows
      @investment_balance_rows ||= begin
        ids = historical_investment_accounts.map(&:id)
        if ids.empty?
          []
        else
          Balance.where(account_id: ids, date: investment_periods.first.begin..investment_periods.last.end).order(:date).to_a
        end
      end
    end

    def investment_statistics
      @investment_statistics ||= ScheduledPayment::RobustEstimator.call(investment_monthly_log_returns, decay: INVESTMENT_DECAY)
    end

    def accessible_payments
      @accessible_payments ||= include_agenda ? family.scheduled_payments.accessible_by(user).to_a : []
    end

    def linked_entry_ids
      @linked_entry_ids ||= ScheduledPaymentEntry.where(scheduled_payment_id: accessible_payments.map(&:id))
        .where.not(entry_id: nil).pluck(:entry_id).to_set
    end

    def explained_by_schedule?(entry)
      return false unless include_agenda

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

    def scenarios
      @scenarios ||= [
        Scenario.new(key: :pessimistic, monthly_cashflow: cashflow_statistics.central - cashflow_statistics.spread),
        Scenario.new(key: :normal, monthly_cashflow: cashflow_statistics.central),
        Scenario.new(key: :optimistic, monthly_cashflow: cashflow_statistics.central + cashflow_statistics.spread)
      ]
    end

    def future_events
      @future_events ||= begin
        range = (start_date + 1.day)..end_date
        stored = ScheduledPaymentEntry.where(scheduled_payment_id: accessible_payments.map(&:id), scheduled_date: range)
          .includes(:entry, :transfer_entry).to_a.group_by(&:scheduled_payment_id)
        accessible_payments.flat_map do |payment|
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
        entries = [ record.entry, record.transfer_entry ].compact.select { |entry| entry.date > start_date }
        included = entries.select { |entry| current_asset_ids.include?(entry.account_id) }
        return if included.empty?

        delta = included.sum { |entry| economic_delta(entry) }
        investment_delta = included.select { |entry| current_investment_ids.include?(entry.account_id) }
          .sum { |entry| economic_delta(entry) }
        return if delta.zero? && investment_delta.zero?

        return Event.new(date: entries.map(&:date).max, delta:, estimated: false, uncertainty: 0.to_d, investment_delta:)
      end

      delta = if payment.transfer?
        transfer_delta(payment)
      elsif current_asset_ids.include?(payment.account_id)
        payment.income? ? converted_amount(payment) : -converted_amount(payment)
      else
        0.to_d
      end
      investment_delta = if payment.transfer?
        scheduled_investment_delta(payment)
      elsif current_investment_ids.include?(payment.account_id)
        delta
      else
        0.to_d
      end
      return if delta.zero? && investment_delta.zero?

      Event.new(
        date:, delta:, estimated: payment.amount_estimated?,
        uncertainty: ScheduledPayment::EstimateUncertainty.for(payment, before: start_date),
        investment_delta:
      )
    end

    def transfer_delta(payment)
      source_included = current_asset_ids.include?(payment.account_id)
      target_included = current_asset_ids.include?(payment.target_account_id)
      return 0.to_d if source_included == target_included

      source_included ? -converted_amount(payment) : converted_amount(payment)
    end

    def scheduled_investment_delta(payment)
      return 0.to_d unless payment.transfer?
      source = current_investment_ids.include?(payment.account_id)
      target = current_investment_ids.include?(payment.target_account_id)
      return 0.to_d if source == target

      source ? -converted_amount(payment) : converted_amount(payment)
    end

    def converted_amount(payment) = convert(payment.amount, payment.currency, start_date)

    def convert(amount, from_currency, date)
      Money.new(amount, from_currency).exchange_to(currency, date:).amount
    rescue Money::ConversionError
      @conversion_failures += 1
      0.to_d
    end

    def projection_dates
      @projection_dates ||= ([ start_date, end_date ] + (start_date..end_date).step(7).to_a +
        future_events.flat_map { |event| [ event.date - 1.day, event.date ] })
        .select { |date| (start_date..end_date).cover?(date) }.uniq.sort
    end

    def projection_point(date)
      elapsed = months_between(start_date, date)
      scenarios.each_with_object({ date: date.iso8601, label: I18n.l(date, format: :short) }) do |scenario, point|
        agenda = future_events.select { |event| event.date <= date }
          .sum { |event| event.delta * estimated_multiplier(event, scenario.key) }
        amount = current_balance.amount + scenario.monthly_cashflow * elapsed +
          irregular_monthly_reserve * elapsed + agenda + investment_market_effect(date, scenario.key)
        point[scenario.key] = { amount: amount.to_f, formatted: Money.new(amount, currency).format }
      end
    end

    def investment_market_effect(date, scenario)
      effect_for_capital(current_investment_balance.amount, months_between(start_date, date), scenario) +
        future_events.select { |event| event.date <= date && !event.investment_delta.zero? }.sum do |event|
          capital = event.investment_delta * estimated_multiplier(event, scenario)
          effect_for_capital(capital, months_between(event.date, date), scenario)
        end
    end

    def effect_for_capital(capital, months, scenario)
      return 0.to_d if capital.zero? || months.zero?

      cumulative_log = investment_statistics.central * months
      uncertainty = investment_statistics.spread * BigDecimal(Math.sqrt(months.to_f).to_s)
      cumulative_log -= uncertainty if scenario == :pessimistic
      cumulative_log += uncertainty if scenario == :optimistic
      capital * (BigDecimal(Math.exp(cumulative_log.to_f).to_s) - 1)
    end

    def months_between(from, to)
      BigDecimal((to - from).to_i.to_s) / DAYS_PER_MONTH
    end

    def estimated_multiplier(event, scenario)
      return 1.to_d unless event.estimated
      return 1.to_d if scenario == :normal

      directional_delta = event.delta.zero? ? event.investment_delta : event.delta
      adverse = directional_delta.negative? ? 1.to_d + event.uncertainty : 1.to_d - event.uncertainty
      scenario == :pessimistic ? adverse : 2.to_d - adverse
    end
end
