require "test_helper"

class ScheduledPayment::ForecastTest < ActiveSupport::TestCase
  fixtures :families, :users, :accounts, :categories

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "combines robust unscheduled history with future Agenda movements" do
    travel_to Date.new(2026, 9, 8) do
      [ Date.new(2026, 6, 10), Date.new(2026, 7, 10), Date.new(2026, 8, 10) ].each do |date|
        create_entry(date:, amount: -1_000, name: "Variable income")
        create_entry(date:, amount: 400, name: "Living costs")
      end
      create_entry(date: Date.new(2026, 8, 12), amount: 9_000, name: "Car", kind: "one_time")

      create_payment(title: "Known bill", amount: 40, payment_type: "expense", start_date: Date.current + 5.days)
      create_payment(title: "Known refund", amount: 100, payment_type: "income", start_date: Date.current + 8.days)

      forecast = build_forecast(horizon: 1)

      assert_equal 3, forecast.history_months
      assert_equal 600, forecast.historical_monthly_savings.amount
      assert_equal 2, forecast.scheduled_event_count
      assert_equal 60, forecast.scheduled_monthly_change.amount
      assert_equal 1, forecast.ignored_one_time_count
      assert_operator forecast.ending_balance(:normal).amount, :>, forecast.current_balance.amount
      assert_operator forecast.projected_monthly_savings.amount, :>, 0
    end
  end

  test "does not estimate historical movements already explained by Agenda" do
    travel_to Date.new(2026, 9, 8) do
      payment = create_payment(
        title: "Rent", amount: 400, payment_type: "expense",
        frequency: "monthly", start_date: Date.new(2026, 6, 10)
      )
      [ Date.new(2026, 6, 10), Date.new(2026, 7, 10), Date.new(2026, 8, 10) ].each do |date|
        create_entry(date:, amount: 400, name: payment.title)
        create_entry(date:, amount: -100, name: "Unscheduled income")
      end

      forecast = build_forecast(horizon: 1)

      assert_equal 100, forecast.historical_monthly_savings.amount
    end
  end

  test "estimated Agenda amounts widen the scenarios" do
    travel_to Date.new(2026, 9, 8) do
      create_payment(
        title: "Estimated utility", amount: 100, payment_type: "expense",
        start_date: Date.current + 2.days, amount_estimated: true
      )

      forecast = build_forecast(horizon: 1)

      assert_operator forecast.ending_balance(:pessimistic).amount, :<, forecast.ending_balance(:normal).amount
      assert_operator forecast.ending_balance(:normal).amount, :<, forecast.ending_balance(:optimistic).amount
    end
  end

  test "scheduled transfers decrease the source and increase the destination" do
    travel_to Date.new(2026, 9, 8) do
      target = accounts(:connected)
      ScheduledPayment.create!(
        family: @family, account: @account, target_account: target,
        title: "Savings transfer", amount: 250, currency: @account.currency,
        frequency: "once", start_date: Date.current + 4.days,
        next_run_date: Date.current + 4.days, status: "active", payment_type: "transfer"
      )

      source_forecast = build_forecast(horizon: 1)
      target_forecast = ScheduledPayment::Forecast.new(
        family: @family, user: @user, account: target, horizon_months: 1
      )

      assert_equal(-250, source_forecast.scheduled_monthly_change.amount)
      assert_equal 250, target_forecast.scheduled_monthly_change.amount
    end
  end

  test "uses only supported horizons" do
    assert_equal 36, build_forecast(horizon: 36).horizon_months
    assert_equal 3, build_forecast(horizon: 99).horizon_months
  end

  private

    def build_forecast(horizon:)
      ScheduledPayment::Forecast.new(
        family: @family, user: @user, account: @account, horizon_months: horizon
      )
    end

    def create_entry(date:, amount:, name:, kind: "standard")
      transaction = Transaction.create!(kind: kind)
      @account.entries.create!(
        date: date, amount: amount, currency: @account.currency,
        name: name, entryable: transaction
      )
    end

    def create_payment(title:, amount:, payment_type:, start_date:, frequency: "once", amount_estimated: false)
      ScheduledPayment.create!(
        family: @family, account: @account, title: title, amount: amount,
        currency: @account.currency, frequency: frequency, start_date: start_date,
        next_run_date: start_date, status: "active", payment_type: payment_type,
        amount_estimated: amount_estimated
      )
    end
end
