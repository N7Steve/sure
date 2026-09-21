require "test_helper"

class ScheduledPayment::ForecastBacktestTest < ActiveSupport::TestCase
  fixtures :families, :users, :accounts

  test "historical fit does not consume transactions after its cutoff" do
    family = families(:dylan_family)
    user = users(:family_admin)
    account = accounts(:depository)
    cutoff = Date.current - 3.months
    before = Transaction.create!
    after = Transaction.create!
    account.entries.create!(
      date: cutoff - 10.days, amount: 100, currency: account.currency,
      name: "Before cutoff", entryable: before
    )
    account.entries.create!(
      date: cutoff + 10.days, amount: 50_000, currency: account.currency,
      name: "After cutoff", entryable: after
    )

    forecast = ScheduledPayment::WealthForecast.new(
      family:, user:, horizon_months: 3, as_of: cutoff, include_agenda: false
    )

    assert_operator forecast.send(:historical_entries).map(&:date).max, :<=, cutoff
    assert_not_includes forecast.send(:historical_entries).map(&:id), after.entry.id
  end

  test "reports bias mae and coverage for both models and required horizons" do
    backtest = ScheduledPayment::ForecastBacktest.new(
      family: families(:dylan_family), user: users(:family_admin), cutoffs: []
    )

    results = backtest.call

    assert_equal 6, results.size
    assert_equal %i[v1 v2], results.map(&:model).uniq.sort
    assert_equal [ 3, 6, 12 ], results.map(&:horizon_months).uniq.sort
    assert results.all? { |result| result.samples.zero? && result.bias.nil? && result.mae.nil? && result.coverage.nil? }
  end
end
