# frozen_string_literal: true

require "test_helper"

class Investment::RoboadvisorPerformanceTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(
      name: "Managed portfolio", balance: 2_030, cash_balance: 0,
      currency: "USD", accountable: Investment.new(subtype: "roboadvisor")
    )
  end

  test "uses Indexa time-weighted index without treating a contribution as return" do
    item = @family.indexa_capital_items.create!(name: "Indexa", api_token: "token")
    provider_account = item.indexa_capital_accounts.create!(
      name: "Indexa managed", indexa_capital_account_id: "IDX12345",
      account_number: "IDX12345", currency: "USD", current_balance: 2_030,
      raw_payload: {
        performance_history: {
          return: {
            pl: 30,
            index: { "20260731" => 1.0, "20260815" => 1.01, "20260831" => 1.03 }
          },
          portfolios: [
            { date: "2026-07-31", total_amount: 1_000 },
            { date: "2026-08-15", total_amount: 2_010 },
            { date: "2026-08-31", total_amount: 2_030 }
          ]
        }
      }
    )
    provider_account.ensure_account_provider!(@account)
    performance = Investment::RoboadvisorPerformance.new(@account)
    period = Date.new(2026, 8, 1)..Date.new(2026, 8, 31)

    assert_in_delta 0.03, performance.rate_for(period), 0.000001
    assert_in_delta 30, performance.total_profit_loss, 0.001
    assert_operator performance.profit_loss_for(period), :<, 50
    assert_operator performance.profit_loss_for(period), :>, 20
  end

  test "balance-only fallback ignores bootstrap valuation and includes later revaluation" do
    @account.balances.create!(
      date: Date.new(2026, 7, 31), balance: 1_000, currency: "USD",
      cash_adjustments: 1_000
    )
    @account.balances.create!(
      date: Date.new(2026, 8, 31), balance: 1_100, currency: "USD",
      start_cash_balance: 1_000, cash_adjustments: 100
    )

    performance = Investment::RoboadvisorPerformance.new(@account)

    assert_equal 100, performance.total_profit_loss
    assert_equal 100, performance.profit_loss_for(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
  end

  test "manual performance includes income and fees but excludes capital transfers" do
    @account.balances.create!(
      date: Date.new(2026, 7, 31), balance: 1_000, currency: "USD",
      cash_adjustments: 1_000
    )
    @account.balances.create!(
      date: Date.new(2026, 8, 31), balance: 1_050, currency: "USD",
      start_cash_balance: 1_000, cash_adjustments: 50
    )
    @account.entries.create!(
      name: "Distribution", date: Date.new(2026, 8, 15), amount: -10,
      currency: "USD", entryable: Transaction.new(kind: "standard")
    )
    @account.entries.create!(
      name: "Management fee", date: Date.new(2026, 8, 20), amount: 4,
      currency: "USD", entryable: Transaction.new(kind: "standard")
    )
    @account.entries.create!(
      name: "Contribution", date: Date.new(2026, 8, 10), amount: -500,
      currency: "USD", entryable: Transaction.new(kind: "investment_contribution")
    )
    @account.entries.create!(
      name: "Rebalance purchase", date: Date.new(2026, 8, 12), amount: 700,
      currency: "USD", entryable: Transaction.new(kind: "standard", investment_activity_label: "Buy")
    )
    performance = Investment::RoboadvisorPerformance.new(@account)
    period = Date.new(2026, 8, 1)..Date.new(2026, 8, 31)

    assert_equal 56, performance.profit_loss_for(period)
    assert_in_delta 0.056, performance.rate_for(period), 0.000001
  end
end
