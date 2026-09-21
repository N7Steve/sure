require "test_helper"

class TransactionForecastBehaviorTest < ActiveSupport::TestCase
  test "legacy one time kind maps to exceptional once" do
    transaction = Transaction.create!(kind: "one_time")

    assert_predicate transaction, :forecast_exceptional_once?
    assert_predicate transaction, :one_time?
  end

  test "irregular recurring is distinct from legacy one time" do
    transaction = Transaction.create!(forecast_behavior: "irregular_recurring")

    assert_predicate transaction, :forecast_irregular_recurring?
    assert_predicate transaction, :standard?
  end
end
