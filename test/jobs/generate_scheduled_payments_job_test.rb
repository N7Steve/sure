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

  test "manual generation is limited to writable schedules in the requested family" do
    family = families(:dylan_family)
    member = users(:family_member)
    attributes = {
      title: "Scoped payment", amount: 25, currency: "USD", frequency: "monthly",
      start_date: Date.current, next_run_date: Date.current, payment_type: "expense"
    }
    writable = family.scheduled_payments.create!(attributes.merge(account: accounts(:depository)))
    read_only = family.scheduled_payments.create!(attributes.merge(account: accounts(:credit_card)))
    foreign_family = families(:empty)
    foreign_account = foreign_family.accounts.create!(name: "Foreign", balance: 0, currency: "USD", accountable: Depository.new)
    foreign = foreign_family.scheduled_payments.create!(attributes.merge(account: foreign_account))

    assert_difference "ScheduledPaymentEntry.count", 1 do
      GenerateScheduledPaymentsJob.perform_now(family.id, member.id)
    end

    assert_equal 1, writable.scheduled_payment_entries.count
    assert_empty read_only.scheduled_payment_entries
    assert_empty foreign.scheduled_payment_entries
    assert_no_difference "ScheduledPaymentEntry.count" do
      GenerateScheduledPaymentsJob.perform_now(family.id, member.id)
    end
  end

  test "a failed schedule rolls back and does not prevent other schedules from running" do
    family = families(:dylan_family)
    attributes = {
      account: accounts(:depository), title: "Job payment", amount: 25, currency: "USD",
      frequency: "monthly", start_date: Date.current, next_run_date: Date.current, payment_type: "expense"
    }
    invalid = family.scheduled_payments.create!(attributes)
    invalid.update_column(:amount, -25)
    valid = family.scheduled_payments.create!(attributes)

    assert_difference "ScheduledPaymentEntry.count", 1 do
      assert_equal 1, GenerateScheduledPaymentsJob.perform_now(family.id)
    end
    assert_empty invalid.scheduled_payment_entries
    assert_equal Date.current, invalid.reload.next_run_date
    assert_equal 1, valid.scheduled_payment_entries.pending.count
  end
end
