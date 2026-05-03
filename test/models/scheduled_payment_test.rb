require "test_helper"

class ScheduledPaymentTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @category = categories(:food_and_drink)
  end

  test "valid scheduled payment" do
    sp = ScheduledPayment.new(
      family: @family, account: @account, category: @category,
      title: "Netflix", amount: 15, currency: "USD",
      frequency: "monthly", frequency_day: 5,
      start_date: Date.current, next_run_date: Date.current,
      payment_type: "expense"
    )
    assert sp.valid?
  end

  test "requires title" do
    sp = @family.scheduled_payments.build(account: @account, amount: 10, currency: "USD",
      frequency: "monthly", frequency_day: 1, start_date: Date.current, next_run_date: Date.current)
    assert_not sp.valid?
    assert_includes sp.errors[:title], "can't be blank"
  end

  test "transfer requires target_account" do
    sp = @family.scheduled_payments.build(
      account: @account, title: "Transfer", amount: 100, currency: "USD",
      frequency: "monthly", frequency_day: 1, start_date: Date.current,
      next_run_date: Date.current, payment_type: "transfer"
    )
    assert_not sp.valid?
    assert_includes sp.errors[:target_account], "can't be blank"
  end

  test "transfer target_account must differ from source" do
    sp = @family.scheduled_payments.build(
      account: @account, target_account: @account,
      title: "Transfer", amount: 100, currency: "USD",
      frequency: "monthly", frequency_day: 1, start_date: Date.current,
      next_run_date: Date.current, payment_type: "transfer"
    )
    assert_not sp.valid?
    assert sp.errors[:target_account].any?
  end

  test "calculate_next_date for monthly handles end of month" do
    sp = @family.scheduled_payments.create!(
      account: @account, title: "Rent", amount: 1000, currency: "USD",
      frequency: "monthly", frequency_day: 31,
      start_date: Date.new(2025, 1, 31), next_run_date: Date.new(2025, 1, 31),
      payment_type: "expense"
    )
    next_date = sp.calculate_next_date(Date.new(2025, 1, 31))
    assert_equal Date.new(2025, 2, 28), next_date
  end

  test "generate_pending_entry creates entry and advances date" do
    sp = @family.scheduled_payments.create!(
      account: @account, title: "Test", amount: 10, currency: "USD",
      frequency: "monthly", frequency_day: 15,
      start_date: Date.current, next_run_date: Date.current,
      payment_type: "expense"
    )

    assert_difference -> { sp.scheduled_payment_entries.count }, 1 do
      sp.generate_pending_entry!
    end

    assert sp.reload.next_run_date > Date.current
  end

  test "generate_pending_entry is idempotent for same date" do
    sp = @family.scheduled_payments.create!(
      account: @account, title: "Test", amount: 10, currency: "USD",
      frequency: "monthly", frequency_day: 15,
      start_date: Date.current, next_run_date: Date.current,
      payment_type: "expense"
    )

    original_next = sp.next_run_date
    sp.generate_pending_entry!
    advanced_next = sp.reload.next_run_date

    # Simulate retry: reset next_run_date to original (as if advance didn't persist)
    sp.update_column(:next_run_date, original_next)
    sp.reload

    assert_no_difference -> { sp.scheduled_payment_entries.count } do
      sp.generate_pending_entry!
    end

    # next_run_date should NOT have advanced again
    assert_equal original_next, sp.reload.next_run_date
  end

  test "completed payment stops generating entries" do
    sp = @family.scheduled_payments.create!(
      account: @account, title: "Limited", amount: 10, currency: "USD",
      frequency: "daily", frequency_day: 0,
      start_date: Date.current, next_run_date: Date.current,
      end_date: Date.current, payment_type: "expense"
    )

    sp.generate_pending_entry!
    sp.reload
    assert_equal "completed", sp.status
  end

  test "due_on_or_before scope returns only active payments due" do
    sp_due = @family.scheduled_payments.create!(
      account: @account, title: "Due", amount: 10, currency: "USD",
      frequency: "monthly", frequency_day: 1,
      start_date: 1.day.ago, next_run_date: 1.day.ago,
      payment_type: "expense"
    )

    sp_future = @family.scheduled_payments.create!(
      account: @account, title: "Future", amount: 20, currency: "USD",
      frequency: "monthly", frequency_day: 15,
      start_date: 1.month.from_now, next_run_date: 1.month.from_now,
      payment_type: "expense"
    )

    results = ScheduledPayment.due_on_or_before(Date.current)
    assert_includes results, sp_due
    assert_not_includes results, sp_future
  end
end
