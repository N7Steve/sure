require "test_helper"

class ScheduledPayment::WealthForecastTest < ActiveSupport::TestCase
  fixtures :families, :users, :accounts

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
  end

  test "starts from all included accessible assets in the family currency" do
    forecast = build_forecast

    assert_equal @family.balance_sheet(user: @user).assets.total, forecast.current_balance.amount
    assert_equal @family.currency, forecast.current_balance.currency.iso_code
  end

  test "excludes assets outside the user's finances" do
    baseline = build_forecast.current_balance.amount
    @family.accounts.create!(
      owner: @user,
      name: "Off-books investment",
      balance: 50_000,
      currency: @family.currency,
      accountable: Investment.new,
      financial_treatment: "outside_finances"
    )

    assert_equal baseline, build_forecast.current_balance.amount
  end

  test "weights recent asset growth more heavily" do
    forecast = build_forecast
    forecast.stubs(:historical_monthly_changes).returns([ 100 ] * 48 + [ 500 ] * 12)

    assert_operator forecast.historical_monthly_savings.amount, :>, BigDecimal("180")
    assert_operator forecast.historical_monthly_savings.amount, :<, BigDecimal("500")
  end

  test "internal scheduled transfers do not change wealth" do
    ScheduledPayment.create!(
      family: @family,
      account: accounts(:depository),
      target_account: accounts(:investment),
      title: "Invest savings",
      amount: 250,
      currency: @family.currency,
      frequency: "once",
      start_date: Date.current + 4.days,
      next_run_date: Date.current + 4.days,
      status: "active",
      payment_type: "transfer"
    )
    forecast = build_forecast(horizon: 1)
    forecast.stubs(:historical_monthly_changes).returns([])

    assert_equal 0, forecast.scheduled_event_count
    assert_equal 0, forecast.scheduled_monthly_change.amount
  end

  test "one-time transactions retain only a quarter of their historical effect" do
    transaction = Transaction.create!(kind: "one_time")
    accounts(:depository).entries.create!(
      date: Date.new(2026, 2, 15),
      amount: 1_000,
      currency: @family.currency,
      name: "Exceptional purchase",
      entryable: transaction
    )
    series = Series.from_raw_values([
      { date: Date.new(2026, 1, 31), value: Money.new(10_000, @family.currency) },
      { date: Date.new(2026, 2, 28), value: Money.new(9_000, @family.currency) }
    ], interval: "1 month")
    forecast = build_forecast
    forecast.stubs(:historical_series).returns(series)
    forecast.stubs(:first_balance_date).returns(Date.new(2026, 1, 1))

    assert_equal(-250, forecast.historical_monthly_savings.amount)
    assert_equal 1, forecast.ignored_one_time_count
  end

  test "Agenda income changes wealth and estimated amounts widen scenarios" do
    ScheduledPayment.create!(
      family: @family,
      account: accounts(:depository),
      title: "Estimated bonus",
      amount: 1_000,
      currency: @family.currency,
      frequency: "once",
      start_date: Date.current + 4.days,
      next_run_date: Date.current + 4.days,
      status: "active",
      payment_type: "income",
      amount_estimated: true
    )
    forecast = build_forecast(horizon: 1)
    forecast.stubs(:historical_monthly_changes).returns([])

    assert_equal 1_000, forecast.scheduled_monthly_change.amount
    assert_operator forecast.ending_balance(:pessimistic).amount, :<, forecast.ending_balance(:normal).amount
    assert_operator forecast.ending_balance(:normal).amount, :<, forecast.ending_balance(:optimistic).amount
  end

  test "uses only supported horizons" do
    assert_equal 36, build_forecast(horizon: 36).horizon_months
    assert_equal 3, build_forecast(horizon: 99).horizon_months
  end

  private

    def build_forecast(horizon: 3)
      ScheduledPayment::WealthForecast.new(
        family: @family,
        user: @user,
        horizon_months: horizon
      )
    end
end
