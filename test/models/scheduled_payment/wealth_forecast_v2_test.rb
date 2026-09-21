require "test_helper"

class ScheduledPayment::WealthForecastV2Test < ActiveSupport::TestCase
  fixtures :families, :users, :accounts

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @cash = accounts(:depository)
    @investment = accounts(:investment)
  end

  test "internal included transfer is neutral while both boundary directions remain cashflow" do
    outside = @family.accounts.create!(
      owner: @user, name: "Outside", balance: 0, currency: @family.currency,
      accountable: Depository.new, financial_treatment: "outside_finances"
    )
    internal_entry = create_transfer(@cash, @investment, 250).outflow_transaction.entry
    outbound_entry = create_transfer(@cash, outside, 300).outflow_transaction.entry
    inbound_entry = create_transfer(outside, @cash, 125).inflow_transaction.entry
    forecast = build_forecast
    forecast.stubs(:historical_entries).returns([ internal_entry, outbound_entry, inbound_entry ])
    forecast.stubs(:cashflow_periods).returns([ (Date.current - 1.month)..(Date.current - 1.day) ])

    assert_equal(-175, forecast.cashflow_residual.amount)
  end

  test "irregular recurring is reserved but excluded from ordinary residual" do
    entry = create_transaction(@cash, 1_200, forecast_behavior: "irregular_recurring")
    forecast = build_forecast
    forecast.stubs(:historical_entries).returns([ entry ])
    forecast.stubs(:cashflow_periods).returns([ (Date.current - 1.month)..(Date.current - 1.day) ])

    assert_equal 0, forecast.cashflow_residual.amount
    assert_equal(-1_200, forecast.irregular_reserve.amount)
  end

  test "contributions and withdrawals are not investment return but market gain and loss are" do
    period = Date.new(2026, 8, 1)..Date.new(2026, 8, 31)
    contribution = balance_row(date: period.begin, start: 1_000, cash_inflows: 500, market: 0)
    withdrawal = balance_row(date: period.begin + 1.day, start: 1_500, cash_outflows: 250, market: 0)
    forecast = build_forecast
    forecast.stubs(:investment_periods).returns([ period ])
    forecast.stubs(:investment_balance_rows).returns([ contribution, withdrawal ])

    assert_equal [ 0 ], forecast.send(:investment_monthly_log_returns)

    gain = balance_row(date: period.begin, start: 1_000, market: 100)
    forecast = build_forecast
    forecast.stubs(:investment_periods).returns([ period ])
    forecast.stubs(:investment_balance_rows).returns([ gain ])
    assert_operator forecast.send(:investment_monthly_log_returns).sole, :>, 0

    loss = balance_row(date: period.begin, start: 1_000, market: -100)
    forecast = build_forecast
    forecast.stubs(:investment_periods).returns([ period ])
    forecast.stubs(:investment_balance_rows).returns([ loss ])
    assert_operator forecast.send(:investment_monthly_log_returns).sole, :<, 0
  end

  test "investment normal scenario compounds and uncertainty grows slower than linearly" do
    forecast_3 = isolated_market_forecast(3)
    forecast_12 = isolated_market_forecast(12)
    normal_growth = forecast_12.ending_balance(:normal).amount - forecast_12.current_balance.amount

    assert_in_delta 1_000 * ((1.01**12) - 1), normal_growth, 5

    width_3 = forecast_3.ending_balance(:optimistic).amount - forecast_3.ending_balance(:pessimistic).amount
    width_12 = forecast_12.ending_balance(:optimistic).amount - forecast_12.ending_balance(:pessimistic).amount
    assert_operator width_12 / width_3, :<, 4
    assert_operator width_12 / width_3, :>, 1
  end

  test "current wealth exactly equals included accessible assets" do
    forecast = build_forecast

    assert_equal @family.balance_sheet(user: @user).assets.total, forecast.current_balance.amount
  end

  test "confirmed Agenda occurrence uses its actual transaction once" do
    date = Date.current + 5.days
    payment = ScheduledPayment.create!(
      family: @family, account: @cash, title: "Confirmed bill", amount: 100,
      currency: @cash.currency, frequency: "once", start_date: date,
      next_run_date: date, status: "active", payment_type: "expense"
    )
    entry = create_transaction(@cash, 120)
    entry.update!(date:)
    payment.scheduled_payment_entries.create!(scheduled_date: date, status: "confirmed", entry:)
    forecast = build_forecast(horizon: 1)
    forecast.stubs(:historical_monthly_changes).returns([])
    forecast.stubs(:investment_monthly_log_returns).returns([])
    forecast.stubs(:irregular_monthly_reserve).returns(0.to_d)

    assert_equal(-120, forecast.scheduled_monthly_change.amount)
    assert_equal forecast.current_balance.amount - 120, forecast.ending_balance(:normal).amount
  end

  test "final scenario composes each component exactly once" do
    forecast = build_forecast(horizon: 3)
    forecast.stubs(:current_balance).returns(Money.new(10_000, @family.currency))
    forecast.stubs(:current_investment_balance).returns(Money.new(1_000, @family.currency))
    forecast.stubs(:historical_monthly_changes).returns([ 100, 100, 100 ])
    forecast.stubs(:irregular_monthly_reserve).returns(-20.to_d)
    forecast.stubs(:investment_monthly_log_returns).returns([ Math.log1p(0.01) ] * 4)
    event = ScheduledPayment::WealthForecast::Event.new(
      date: Date.current + 5.days, delta: -50.to_d, estimated: false,
      uncertainty: 0.to_d, investment_delta: 0.to_d
    )
    forecast.stubs(:future_events).returns([ event ])
    months = BigDecimal((forecast.end_date - forecast.start_date).to_i.to_s) /
      ScheduledPayment::WealthForecast::DAYS_PER_MONTH
    expected = 10_000 + (100 - 20) * months - 50 + 1_000 * (BigDecimal(Math.exp(Math.log1p(0.01) * months.to_f).to_s) - 1)

    assert_in_delta expected, forecast.ending_balance(:normal).amount, 0.01
  end

  private

    def build_forecast(horizon: 3)
      ScheduledPayment::WealthForecast.new(family: @family, user: @user, horizon_months: horizon)
    end

    def create_transaction(account, amount, forecast_behavior: "normal")
      transaction = Transaction.create!(forecast_behavior:)
      account.entries.create!(
        date: Date.current - 10.days, amount:, currency: account.currency,
        name: "Test movement", entryable: transaction
      )
    end

    def create_transfer(source, target, amount)
      outflow = create_transaction(source, amount)
      inflow = create_transaction(target, -amount)
      Transfer.create!(
        outflow_transaction: outflow.entryable,
        inflow_transaction: inflow.entryable,
        status: "confirmed"
      )
    end

    def balance_row(date:, start:, market:, cash_inflows: 0, cash_outflows: 0)
      Balance.new(
        account: @investment, date:, currency: @investment.currency, balance: start + market,
        start_cash_balance: start, start_non_cash_balance: 0,
        cash_inflows:, cash_outflows:, non_cash_inflows: 0, non_cash_outflows: 0,
        net_market_flows: market, flows_factor: 1
      ).tap do |row|
        row.define_singleton_method(:start_balance) { BigDecimal(start.to_s) }
      end
    end

    def isolated_market_forecast(horizon)
      forecast = build_forecast(horizon:)
      forecast.stubs(:historical_monthly_changes).returns([])
      forecast.stubs(:irregular_monthly_reserve).returns(0.to_d)
      forecast.stubs(:future_events).returns([])
      forecast.stubs(:current_balance).returns(Money.new(1_000, @family.currency))
      forecast.stubs(:current_investment_balance).returns(Money.new(1_000, @family.currency))
      forecast.stubs(:investment_monthly_log_returns).returns([
        Math.log1p(-0.01), Math.log1p(0.01), Math.log1p(0.01), Math.log1p(0.03)
      ])
      forecast
    end
end
