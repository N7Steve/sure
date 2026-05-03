require "test_helper"

class GenerateScheduledPaymentsJobTest < ActiveJob::TestCase
  fixtures :families, :accounts, :categories

  test "generates pending entries up to today and advances next_run_date" do
    family = families(:dylan_family)
    account = accounts(:depository)
    category = categories(:food_and_drink)

    sp = ScheduledPayment.create!(
      family: family,
      account: account,
      category: category,
      title: "Spotify",
      amount: 10,
      currency: account.currency,
      frequency: "daily",
      frequency_day: 0,
      start_date: 1.day.ago.to_date,
      next_run_date: 1.day.ago.to_date,
      status: "active",
      payment_type: "expense"
    )

    # Run job
    assert_difference -> { ScheduledPaymentEntry.count }, +2 do
      GenerateScheduledPaymentsJob.perform_now
    end

    sp.reload
    assert sp.next_run_date > Date.current, "next_run_date should be advanced beyond today"

    # Confirm one entry produces a real transaction entry
    pending_entry = sp.scheduled_payment_entries.order(:scheduled_date).first
    assert_equal "pending", pending_entry.status

    pending_entry.confirm!
    pending_entry.reload
    assert_equal "confirmed", pending_entry.status
    assert pending_entry.entry.present?, "should create Entry on confirm"

    # Entry should belong to the SP account and have proper sign
    entry = pending_entry.entry
    assert_equal account.id, entry.account_id
    assert_equal 10.to_d, entry.amount, "expense outflow should be positive amount"
  end
end
