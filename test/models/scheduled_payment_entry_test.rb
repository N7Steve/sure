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

  test "confirm applies scheduled payment tags to created entry" do
    tag = @family.tags.create!(name: "Recurring Bills")
    @sp.tags << tag

    spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    spe.confirm!

    assert_includes spe.reload.entry.entryable.tags, tag
  end

  test "retract! destroys the confirmed entry and marks SPE as skipped" do
    spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")
    spe.confirm!
    entry_id = spe.reload.entry.id

    spe.retract!

    assert_not Entry.exists?(entry_id), "Entry should be destroyed after retract"
    assert_equal "skipped", spe.reload.status
    assert_equal "retracted_by_user", spe.reload.rejection_reason
    assert_nil spe.reload.entry_id
  end

  test "retract! does nothing if SPE is not confirmed" do
    spe = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    assert_no_difference -> { Entry.count } do
      spe.retract!
    end
    assert_equal "pending", spe.reload.status
  end

  test "confirm on a stale pending instance does not duplicate the ledger entry" do
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    stale = ScheduledPaymentEntry.find(occurrence.id)
    occurrence.confirm!

    assert_no_difference [ "Entry.count", "Transaction.count" ] do
      stale.confirm!
    end
    assert_equal occurrence.reload.entry_id, stale.reload.entry_id
  end

  test "skip and reject cannot overwrite a confirmation seen by a stale request" do
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    stale_skip = ScheduledPaymentEntry.find(occurrence.id)
    stale_reject = ScheduledPaymentEntry.find(occurrence.id)
    occurrence.confirm!

    stale_skip.skip!
    stale_reject.reject!

    assert_predicate occurrence.reload, :confirmed?
    assert occurrence.entry_id.present?
  end

  test "retraction of a transfer removes both entries once" do
    @sp.update!(payment_type: "transfer", target_account: accounts(:credit_card))
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    occurrence.confirm!
    stale = ScheduledPaymentEntry.find(occurrence.id)

    assert_difference [ "Entry.count", "Transaction.count" ], -2 do
      assert_difference "Transfer.count", -1 do
        occurrence.retract!
      end
    end
    assert_no_difference "Entry.count" do
      stale.retract!
    end
    assert_predicate occurrence.reload, :skipped?
    assert_nil occurrence.entry_id
    assert_nil occurrence.transfer_entry_id
  end

  test "restoring a future skip rewinds the cursor so it will run when due" do
    date = Date.current + 10.days
    @sp.update!(start_date: date, next_run_date: date, end_date: date)
    occurrence = @sp.skip_on!(date)
    assert_predicate @sp.reload, :completed?

    occurrence.restore!

    assert_not ScheduledPaymentEntry.exists?(occurrence.id)
    assert_predicate @sp.reload, :active?
    assert_equal date, @sp.next_run_date
    generated = @sp.generate_pending_entry!(through: date)
    assert_equal date, generated.scheduled_date
    assert_predicate generated, :pending?
  end

  test "restoring a past skip keeps the original immediate confirmation behavior" do
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.yesterday, status: "skipped")

    assert_difference "Entry.count", 1 do
      occurrence.restore!
    end
    assert_predicate occurrence.reload, :confirmed?
    assert_equal Date.yesterday, occurrence.entry.date
  end

  test "reverting future entries in any order keeps the earliest next run date" do
    @sp.update!(frequency: "daily", start_date: Date.tomorrow, next_run_date: Date.tomorrow)
    first = @sp.generate_pending_entry!
    second = @sp.generate_pending_entry!

    assert first.revert_future!
    assert second.revert_future!

    assert_equal Date.tomorrow, @sp.reload.next_run_date
    assert_empty @sp.scheduled_payment_entries
  end

  test "a stale future reversion cannot delete a confirmed occurrence" do
    @sp.update!(start_date: Date.tomorrow, next_run_date: Date.tomorrow)
    occurrence = @sp.generate_pending_entry!
    stale = ScheduledPaymentEntry.find(occurrence.id)
    occurrence.confirm!

    assert_no_difference [ "Entry.count", "ScheduledPaymentEntry.count" ] do
      assert_nil stale.revert_future!
      assert_nil stale.purge_pending!
    end
    assert_predicate occurrence.reload, :confirmed?
  end

  test "confirmation honors the edited amount and date" do
    @sp.update!(payment_type: "income")
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "rejected", rejection_reason: "old")

    occurrence.confirm!(date_override: Date.yesterday, amount_override: BigDecimal("31.45"))

    assert_equal(-BigDecimal("31.45"), occurrence.reload.entry.amount)
    assert_equal Date.yesterday, occurrence.entry.date
    assert_nil occurrence.rejection_reason
  end

  test "invalid confirmation amounts leave the ledger unchanged" do
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)

    [ BigDecimal("-1"), BigDecimal("NaN"), BigDecimal("Infinity") ].each do |amount|
      assert_no_difference [ "Entry.count", "Transaction.count" ] do
        assert_raises(ArgumentError) { occurrence.confirm!(amount_override: amount) }
      end
      assert_predicate occurrence.reload, :pending?
    end
  end

  test "a legacy inconsistent state cannot create a second ledger entry" do
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    occurrence.confirm!
    occurrence.update_column(:status, "skipped")

    assert_no_difference "Entry.count" do
      assert_raises(ActiveRecord::RecordInvalid) { occurrence.confirm! }
    end
  end

  test "transfer confirmation converts the destination amount at its actual date" do
    target = accounts(:credit_card)
    target.update!(currency: "EUR")
    @sp.update!(payment_type: "transfer", target_account: target)
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    ExchangeRate.expects(:find_or_fetch_rate).with(from: "USD", to: "EUR", date: Date.yesterday)
      .returns(OpenStruct.new(rate: BigDecimal("0.9")))

    occurrence.confirm!(date_override: Date.yesterday)

    assert_equal BigDecimal("25"), occurrence.reload.entry.amount
    assert_equal(-BigDecimal("22.5"), occurrence.transfer_entry.amount)
    assert_equal "EUR", occurrence.transfer_entry.currency
  end

  test "a missing transfer exchange rate rolls back both sides" do
    target = accounts(:credit_card)
    target.update!(currency: "EUR")
    @sp.update!(payment_type: "transfer", target_account: target)
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    ExchangeRate.stubs(:find_or_fetch_rate).returns(nil)

    assert_no_difference [ "Entry.count", "Transaction.count", "Transfer.count" ] do
      assert_raises(Money::ConversionError) { occurrence.confirm! }
    end
    assert_predicate occurrence.reload, :pending?
    assert_nil occurrence.entry_id
    assert_nil occurrence.transfer_entry_id
  end

  test "transfer tags are applied and updated on both sides" do
    @sp.update!(payment_type: "transfer", target_account: accounts(:credit_card), tags: [ tags(:one) ])
    occurrence = @sp.scheduled_payment_entries.create!(scheduled_date: Date.current)
    occurrence.confirm!

    [ occurrence.reload.entry, occurrence.transfer_entry ].each do |entry|
      assert_equal [ tags(:one).id ], entry.entryable.tag_ids
    end

    @sp.update!(tags: [ tags(:two) ])
    @sp.sync_confirmed_entries!

    [ occurrence.reload.entry, occurrence.transfer_entry ].each do |entry|
      assert_equal [ tags(:two).id ], entry.entryable.tag_ids
    end
  end
end
