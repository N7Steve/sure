require "test_helper"

class ScheduledPaymentRobustnessTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = accounts(:depository)
  end

  test "a stale generator does not generate beyond its cutoff" do
    payment = create_payment
    stale = ScheduledPayment.find(payment.id)
    payment.generate_pending_entry!(through: Date.current)

    assert_no_difference "ScheduledPaymentEntry.count" do
      assert_nil stale.generate_pending_entry!(through: Date.current)
    end
    assert_equal 1, payment.reload.occurrences_count
  end

  test "a stale generator respects a newly paused schedule" do
    payment = create_payment
    stale = ScheduledPayment.find(payment.id)
    payment.update!(status: "paused")

    assert_no_difference "ScheduledPaymentEntry.count" do
      assert_nil stale.generate_pending_entry!
    end
  end

  test "an expired cursor completes without creating an occurrence" do
    payment = create_payment(start_date: 10.days.ago.to_date, end_date: Date.yesterday)

    assert_no_difference "ScheduledPaymentEntry.count" do
      assert_nil payment.generate_pending_entry!
    end
    assert_predicate payment.reload, :completed?
  end

  test "generation and automatic confirmation roll back if advancement fails" do
    payment = create_payment(auto_confirm: true)
    original_date = payment.next_run_date
    payment.stubs(:advance_next_run_date!).raises(ActiveRecord::RecordInvalid.new(payment))

    assert_no_difference [ "ScheduledPaymentEntry.count", "Entry.count", "Transaction.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) { payment.generate_pending_entry! }
    end
    assert_equal original_date, payment.reload.next_run_date
  end

  test "skipping a confirmed date keeps its state and ledger link" do
    payment = create_payment
    occurrence = payment.confirm_on!(Date.current)
    entry_id = occurrence.entry_id

    assert_no_difference "Entry.count" do
      payment.skip_on!(Date.current)
    end
    assert_predicate occurrence.reload, :confirmed?
    assert_equal entry_id, occurrence.entry_id
  end

  test "manual actions cannot create dates outside the schedule" do
    payment = create_payment

    assert_no_difference [ "ScheduledPaymentEntry.count", "Entry.count" ] do
      assert_raises(ArgumentError) { payment.confirm_on!(Date.current + 1.day) }
      assert_raises(ArgumentError) { payment.skip_on!(Date.yesterday) }
    end
  end

  test "old daily schedules still project recent occurrences" do
    payment = create_payment(start_date: Date.new(1980, 1, 1), frequency: "daily")
    range = Date.current..(Date.current + 2.days)

    assert_equal range.to_a, payment.occurrences_in(range)
  end

  test "monthly projection preserves the anchor day through short months" do
    payment = create_payment(start_date: Date.new(2024, 1, 31))

    assert_equal [ Date.new(2024, 2, 29), Date.new(2024, 3, 31) ],
      payment.occurrences_in(Date.new(2024, 2, 1)..Date.new(2024, 3, 31))
  end

  test "quarterly and biweekly projection preserve interval phase" do
    quarterly = create_payment(start_date: Date.new(2024, 1, 31), frequency: "quarterly")
    biweekly = create_payment(start_date: Date.new(2024, 1, 1), frequency: "biweekly")

    assert_equal [ Date.new(2024, 4, 30) ],
      quarterly.occurrences_in(Date.new(2024, 3, 1)..Date.new(2024, 5, 31))
    assert_equal [ Date.new(2024, 2, 12), Date.new(2024, 2, 26) ],
      biweekly.occurrences_in(Date.new(2024, 2, 1)..Date.new(2024, 2, 29))
  end

  test "historical matching ignores income and valuations for an expense" do
    payment = create_payment(start_date: Date.new(2020, 1, 15), next_run_date: Date.new(2020, 1, 15))
    create_historical_entry(payment, amount: -25)
    @account.entries.create!(name: payment.title, date: payment.start_date,
      amount: 25, currency: "USD", entryable: Valuation.new)

    assert_no_difference "ScheduledPaymentEntry.count" do
      payment.link_matching_entries!(@user)
    end
  end

  test "historical matching preserves skipped occurrences and unpaid gaps" do
    payment = create_payment(start_date: Date.new(2020, 1, 15), next_run_date: Date.new(2020, 1, 15))
    skipped = payment.scheduled_payment_entries.create!(scheduled_date: Date.new(2020, 2, 15), status: "skipped")
    create_historical_entry(payment, date: skipped.scheduled_date)
    march = create_historical_entry(payment, date: Date.new(2020, 3, 15))

    payment.link_matching_entries!(@user)

    assert_predicate skipped.reload, :skipped?
    assert_nil skipped.entry_id
    assert_equal march.id, payment.scheduled_payment_entries.confirmed.sole.entry_id
    assert_equal Date.new(2020, 1, 15), payment.reload.next_run_date
  end

  test "historical matching never links one entry to two schedules" do
    first = create_payment(start_date: Date.new(2020, 1, 15), next_run_date: Date.new(2020, 1, 15))
    second = create_payment(start_date: first.start_date, next_run_date: first.start_date)
    entry = create_historical_entry(first)
    first.link_matching_entries!(@user)

    assert_no_difference "ScheduledPaymentEntry.count" do
      second.link_matching_entries!(@user)
    end
    assert_equal entry.id, first.scheduled_payment_entries.confirmed.sole.entry_id
  end

  test "transfer access requires both accounts and write permission" do
    payment = create_payment(payment_type: "transfer", target_account: accounts(:credit_card))
    member = users(:family_member)
    assert_includes @family.scheduled_payments.accessible_by(member), payment
    assert_not_includes @family.scheduled_payments.writable_by(member), payment

    account_shares(:credit_card_shared_with_member).destroy!
    assert_not_includes @family.scheduled_payments.accessible_by(member), payment
  end

  test "changing the source does not grant write access to old ledger entries" do
    payment = create_payment(account: accounts(:credit_card))
    payment.confirm_on!(Date.current)
    payment.update!(account: @account)

    assert_raises(ActiveRecord::RecordNotFound) do
      payment.ensure_writable_by!(users(:family_member))
    end
  end

  test "model rejects associations from another family" do
    payment = create_payment
    foreign = families(:empty)
    payment.account = Account.new(family: foreign)
    payment.category = Category.new(family: foreign)
    payment.merchant = FamilyMerchant.new(family: foreign)
    payment.tags = [ foreign.tags.create!(name: "Foreign") ]

    assert_not payment.valid?
    %i[account category merchant tags].each { |attribute| assert payment.errors[attribute].any? }
  end

  test "invalid amount and end date are rejected" do
    payment = create_payment
    payment.assign_attributes(amount: -1, end_date: payment.start_date - 1.day)
    assert_not payment.valid?
    assert payment.errors[:amount].any?
    assert payment.errors[:end_date].any?

    payment.assign_attributes(amount: 25, end_date: nil, payment_type: nil)
    assert_not payment.valid?
    assert payment.errors[:payment_type].any?
  end

  test "deleting either transfer account removes the schedule before its ledger entries" do
    [ :source, :destination ].each do |side|
      source = @family.accounts.create!(name: "Source #{side}", balance: 0, currency: "USD", accountable: Depository.new)
      destination = @family.accounts.create!(name: "Destination #{side}", balance: 0, currency: "USD", accountable: Depository.new)
      payment = create_payment(account: source, target_account: destination, payment_type: "transfer")
      occurrence = payment.confirm_on!(Date.current)
      entry_ids = [ occurrence.entry_id, occurrence.transfer_entry_id ]

      (side == :source ? source : destination).destroy!

      assert_not ScheduledPayment.exists?(payment.id)
      assert_not ScheduledPaymentEntry.exists?(occurrence.id)
      assert_empty Entry.where(id: entry_ids)
    end
  end

  test "replacing a category preserves it on the schedule" do
    category = @family.categories.create!(name: "Scheduled category", color: Category::COLORS.first, lucide_icon: "circle")
    payment = create_payment(category: category)
    replacement = categories(:food_and_drink)

    category.replace_and_destroy!(replacement)

    assert_equal replacement.id, payment.reload.category_id
  end

  test "deleting an optional merchant preserves the schedule" do
    merchant = @family.merchants.create!(name: "Scheduled merchant")
    payment = create_payment(merchant: merchant)

    merchant.destroy!

    assert_nil payment.reload.merchant_id
    assert_predicate payment, :active?
  end

  private
    def create_payment(**attributes)
      @family.scheduled_payments.create!({
        account: @account, title: "Robustness payment", amount: 25, currency: "USD",
        start_date: Date.current, next_run_date: Date.current, frequency: "monthly", payment_type: "expense"
      }.merge(attributes))
    end

    def create_historical_entry(payment, date: payment.start_date, amount: 25)
      @account.entries.create!(name: payment.title, date: date, amount: amount,
        currency: payment.currency, entryable: Transaction.new)
    end
end
