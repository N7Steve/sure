require "test_helper"

class ScheduledPayment::AgendaTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @month = Date.new(2026, 9, 1)
  end

  test "remaining expenses exclude confirmed skipped income and transfers and keep currencies separate" do
    create_payment(amount: 20)
    create_payment(amount: 30)
    create_payment(amount: 40, currency: "EUR")
    create_payment(amount: 100, payment_type: "income")
    create_payment(amount: 200, payment_type: "transfer", target_account: accounts(:credit_card))
    confirmed = create_payment(amount: 60)
    confirmed.scheduled_payment_entries.create!(scheduled_date: @month, status: "confirmed")
    skipped = create_payment(amount: 70)
    skipped.scheduled_payment_entries.create!(scheduled_date: @month, status: "skipped")

    Money.any_instance.expects(:exchange_to).never
    agenda = build_agenda

    assert_equal [ Money.new(40, "EUR"), Money.new(50, "USD") ], agenda.remaining_expenses
    assert_equal 5, agenda.pending_count
    assert_equal 7, agenda.active_count
    assert_equal 7, agenda.month_occurrences.size
  end

  test "planning totals normalize recurring expenses and keep currencies separate" do
    housing = categories(:housing)
    create_payment(amount: 120, frequency: "monthly", category: housing)
    create_payment(amount: 300, frequency: "quarterly", category: housing, amount_estimated: true)
    create_payment(amount: 1200, frequency: "yearly", currency: "EUR")
    create_payment(amount: 900, frequency: "once")
    create_payment(amount: 500, frequency: "monthly", payment_type: "income")
    create_payment(amount: 50, frequency: "monthly", status: "paused")

    agenda = build_agenda

    assert_equal [ Money.new(220, "USD"), Money.new(100, "EUR") ].sort_by(&:currency),
      agenda.recurring_monthly_expenses.sort_by(&:currency)
    assert_equal [ Money.new(2640, "USD"), Money.new(1200, "EUR") ].sort_by(&:currency),
      agenda.recurring_annual_expenses.sort_by(&:currency)
    assert_equal [ Money.new(100, "USD"), Money.new(100, "EUR") ].sort_by(&:currency),
      agenda.monthly_provisions.sort_by(&:currency)
    assert_predicate agenda, :planning_has_estimates?

    housing_row = agenda.planning_breakdown.find { |row| row.category == housing }
    assert_equal BigDecimal("220"), housing_row.monthly_amount
    assert_equal BigDecimal("100"), housing_row.provision_amount
    assert housing_row.amount_estimated
  end

  test "calendar projects whole weeks without adding adjacent months to totals or writing occurrences" do
    payment = create_payment(frequency: "daily", start_date: @month - 1.day, next_run_date: @month - 1.day)

    assert_no_difference [ "Entry.count", "ScheduledPaymentEntry.count" ] do
      agenda = build_agenda
      assert_equal Date.new(2026, 8, 31), agenda.days.first.date
      assert_equal Date.new(2026, 10, 4), agenda.days.last.date
      assert_equal 35, agenda.days.size
      assert_equal 30, agenda.month_occurrences.size
      assert_equal [ Money.new(750, "USD") ], agenda.remaining_expenses
      assert_equal 30, agenda.occupied_month_days.size
    end
    assert_equal @month - 1.day, payment.reload.next_run_date
  end

  test "paused and completed schedules retain stored occurrences without projecting new ones" do
    %w[paused completed].each do |status|
      payment = create_payment(status: status, frequency: "daily")
      payment.scheduled_payment_entries.create!(scheduled_date: @month + 3.days, status: "pending")
    end

    agenda = build_agenda
    assert_equal 0, agenda.active_count
    assert_equal 2, agenda.month_occurrences.size
    assert_equal 2, agenda.pending_count
  end

  test "confirmed occurrence uses actual override amount and currency after schedule changes" do
    payment = create_payment
    occurrence = payment.confirm_on!(@month, amount_override: 19)
    payment.update!(amount: 90, currency: "EUR", payment_type: "income")

    row = build_agenda.month_occurrences.sole
    assert_equal occurrence.id, row.entry_id
    assert_equal Money.new(19, "USD"), row.amount_money
    assert_equal Money.new(-19, "USD"), row.display_amount_money
    assert_equal 0, build_agenda.pending_count
  end

  test "read only destination allows visibility but no management" do
    payment = create_payment(payment_type: "transfer", target_account: accounts(:credit_card))
    agenda = build_agenda(user: users(:family_member))

    assert_includes agenda.payments.map(&:id), payment.id
    assert_equal 1, agenda.month_occurrences.size
    assert_not agenda.writable?(payment)
  end

  test "historical entry permissions continue to restrict a moved schedule" do
    payment = create_payment(account: accounts(:credit_card))
    payment.confirm_on!(@month)
    payment.update!(account: accounts(:depository))

    agenda = build_agenda(user: users(:family_member))
    assert_equal 1, agenda.month_occurrences.size
    assert_not agenda.writable?(payment)
  end

  test "foreign family schedules are excluded" do
    account = families(:empty).accounts.create!(name: "Foreign", currency: "USD", balance: 0, accountable: Depository.new)
    create_payment(family: families(:empty), account: account)

    assert_empty build_agenda.payments
    assert_empty build_agenda.month_occurrences
  end

  test "inaccessible transfer destinations and historical amounts are not exposed" do
    hidden_transfer = create_payment(payment_type: "transfer", target_account: accounts(:connected))
    moved_payment = create_payment(account: accounts(:connected))
    moved_payment.confirm_on!(@month)
    moved_payment.update!(account: accounts(:depository))

    agenda = build_agenda(user: users(:family_member))
    assert_not_includes agenda.payments.map(&:id), hidden_transfer.id
    assert_includes agenda.payments.map(&:id), moved_payment.id
    assert_empty agenda.month_occurrences
    assert_not agenda.writable?(moved_payment)
  end

  test "older pending warning excludes future and resolved records" do
    travel_to @month + 10.days do
      payment = create_payment(start_date: @month - 2.months)
      older = payment.scheduled_payment_entries.create!(scheduled_date: @month - 1.month, status: "pending")
      payment.scheduled_payment_entries.create!(scheduled_date: @month - 2.months, status: "skipped")
      payment.scheduled_payment_entries.create!(scheduled_date: @month, status: "pending")

      assert_equal [ older.id ], build_agenda.older_pending.map(&:id)
    end
  end

  test "invalid months fall back to current month and month-only URLs are supported" do
    travel_to @month do
      [ nil, "bad", "2026-13", "999999-09-01" ].each do |value|
        assert_equal @month, ScheduledPayment::Agenda.month_from(value)
      end
      assert_equal Date.new(2027, 2, 1), ScheduledPayment::Agenda.month_from("2027-02")
      assert_equal @month, ScheduledPayment::Agenda.month_from("2026-09-17")
    end
  end

  private

    def build_agenda(user: @user)
      ScheduledPayment::Agenda.new(family: @family, user: user, month: @month.iso8601)
    end

    def create_payment(**attributes)
      ScheduledPayment.create!({
        family: @family, account: accounts(:depository), title: "Agenda payment", amount: 25,
        currency: "USD", frequency: "monthly", payment_type: "expense",
        start_date: @month, next_run_date: @month
      }.merge(attributes))
    end
end
