require "test_helper"

class ScheduledPaymentEntryTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @category = categories(:food_and_drink)
    @sp = ScheduledPayment.create!(
      family: @family, account: @account, category: @category,
      title: "Test Payment", amount: 25, currency: "USD",
      frequency: "monthly", frequency_day: 10,
      start_date: Date.current, next_run_date: Date.current,
      payment_type: "expense"
    )
  end

  test "confirm creates a real entry for expense" do
    pending_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    assert_difference -> { Entry.count }, 1 do
      pending_entry.confirm!
    end

    pending_entry.reload
    assert_equal "confirmed", pending_entry.status
    assert pending_entry.entry.present?
    assert_equal 25.to_d, pending_entry.entry.amount
    assert_equal @account.id, pending_entry.entry.account_id
  end

  test "confirm creates a real entry for income with negative amount" do
    @sp.update!(payment_type: "income")
    pending_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    pending_entry.confirm!
    pending_entry.reload

    assert_equal(-25.to_d, pending_entry.entry.amount)
  end

  test "reject marks entry as rejected with reason" do
    pending_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    pending_entry.reject!("Cancelled this month")
    pending_entry.reload

    assert_equal "rejected", pending_entry.status
    assert_equal "Cancelled this month", pending_entry.rejection_reason
  end

  test "skip marks entry as skipped" do
    pending_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    pending_entry.skip!
    assert_equal "skipped", pending_entry.reload.status
  end

  test "confirm on non-pending entry does nothing" do
    confirmed_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "confirmed")

    assert_no_difference -> { Entry.count } do
      confirmed_entry.confirm!
    end
  end

  test "confirm for transfer creates two entries and a Transfer record" do
    target = accounts(:credit_card)
    @sp.update!(payment_type: "transfer", target_account: target)

    pending_entry = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    assert_difference -> { Entry.count }, 2 do
      assert_difference -> { Transfer.count }, 1 do
        pending_entry.confirm!
      end
    end

    pending_entry.reload
    assert_equal "confirmed", pending_entry.status
    assert pending_entry.entry.present?
    assert pending_entry.transfer_entry.present?
  end

  test "cannot destroy an entry linked to a confirmed scheduled payment entry" do
    pending_spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    pending_spe.confirm!
    linked_entry = pending_spe.reload.entry

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      linked_entry.destroy!
    end
  end

  test "can destroy an entry after its scheduled payment is deleted" do
    pending_spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    pending_spe.confirm!
    linked_entry = pending_spe.reload.entry

    @sp.destroy!

    assert_nothing_raised do
      linked_entry.reload.destroy!
    end
  end

  test "from_scheduled_payment? returns false for a new unlinked entry" do
    entry = @sp.account.entries.create!(
      date: Date.current, amount: 10, currency: "USD",
      name: "Manual entry", entryable: Transaction.create!
    )
    assert_not entry.from_scheduled_payment?
  end

  test "from_scheduled_payment? returns true for a confirmed scheduled payment entry" do
    pending_spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    pending_spe.confirm!
    assert pending_spe.reload.entry.from_scheduled_payment?
  end

  test "source_scheduled_payment returns the linked ScheduledPayment" do
    pending_spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    pending_spe.confirm!
    assert_equal @sp, pending_spe.reload.entry.source_scheduled_payment
  end
end
