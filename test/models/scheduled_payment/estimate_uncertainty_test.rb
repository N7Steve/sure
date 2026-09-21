require "test_helper"

class ScheduledPayment::EstimateUncertaintyTest < ActiveSupport::TestCase
  fixtures :families, :users, :accounts

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @payment = ScheduledPayment.create!(
      family: @family, account: @account, title: "Variable utility", amount: 100,
      currency: @account.currency, frequency: "monthly", start_date: 6.months.ago.to_date,
      next_run_date: 1.month.from_now.to_date, status: "active", payment_type: "expense",
      amount_estimated: true
    )
  end

  test "uses learned robust error dispersion after four confirmations" do
    [ 80, 90, 110, 120 ].each_with_index { |amount, index| add_confirmation(amount, index.months.ago.to_date) }

    uncertainty = ScheduledPayment::EstimateUncertainty.for(@payment, before: Date.current)

    assert_operator uncertainty, :>, 0
    assert_not_equal BigDecimal("0.15"), uncertainty
  end

  test "falls back to fifteen percent with insufficient history" do
    3.times { |index| add_confirmation(100 + index, index.months.ago.to_date) }

    assert_equal BigDecimal("0.15"), ScheduledPayment::EstimateUncertainty.for(@payment, before: Date.current)
  end

  private

    def add_confirmation(amount, date)
      transaction = Transaction.create!
      entry = @account.entries.create!(date:, amount:, currency: @account.currency, name: @payment.title, entryable: transaction)
      @payment.scheduled_payment_entries.create!(scheduled_date: date, status: "confirmed", entry:)
    end
end
