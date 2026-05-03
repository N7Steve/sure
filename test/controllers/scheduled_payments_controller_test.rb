require "test_helper"

class ScheduledPaymentsControllerTest < ActionDispatch::IntegrationTest
  fixtures :families, :accounts, :categories, :users

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @account = accounts(:depository)
    @category = categories(:food_and_drink)
  end

  test "index loads successfully" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Netflix",
      amount: 15,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: 1,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    get scheduled_payments_url
    assert_response :success
    assert_includes response.body, I18n.t("scheduled_payments.title")
    assert_includes response.body, sp.title
  end

  test "create scheduled payment" do
    assert_difference -> { ScheduledPayment.count }, +1 do
      post scheduled_payments_url, params: {
        scheduled_payment: {
          title: "Spotify",
          amount: 10,
          currency: @account.currency,
          frequency: "monthly",
          frequency_day: 5,
          start_date: Date.current,
          end_date: nil,
          account_id: @account.id,
          category_id: @category.id,
          payment_type: "expense",
          auto_confirm: false
        }
      }
    end

    sp = ScheduledPayment.order("created_at DESC").first
    assert_redirected_to scheduled_payments_url
    assert_equal sp.start_date, sp.next_run_date
    assert_equal @family.id, sp.family_id
  end

  test "update scheduled payment" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Gym",
      amount: 30,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: 10,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    patch scheduled_payment_url(sp), params: { scheduled_payment: { title: "Gym Membership" } }
    assert_redirected_to scheduled_payments_url
    assert_equal "Gym Membership", sp.reload.title
  end

  test "destroy scheduled payment" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Hulu",
      amount: 8,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: 2,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    assert_difference -> { ScheduledPayment.count }, -1 do
      delete scheduled_payment_url(sp)
    end
    assert_redirected_to scheduled_payments_url
  end

  test "toggle status between active and paused" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Prime",
      amount: 12,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: 3,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    post toggle_status_scheduled_payment_url(sp)
    assert_redirected_to scheduled_payments_url
    assert_equal "paused", sp.reload.status

    post toggle_status_scheduled_payment_url(sp)
    assert_redirected_to scheduled_payments_url
    assert_equal "active", sp.reload.status
  end

  test "confirm pending entry creates real entry and marks confirmed" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Spotify",
      amount: 10,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: Date.current.day,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    pending = sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    assert_difference -> { Entry.count }, +1 do
      post confirm_entry_scheduled_payment_url(sp), params: { entry_id: pending.id }
    end
    assert_redirected_to scheduled_payments_url

    pending.reload
    assert_equal "confirmed", pending.status
    assert pending.entry.present?
  end

  test "reject pending entry marks rejected" do
    sp = ScheduledPayment.create!(
      family: @family,
      account: @account,
      category: @category,
      title: "Spotify",
      amount: 10,
      currency: @account.currency,
      frequency: "monthly",
      frequency_day: Date.current.day,
      start_date: Date.current,
      next_run_date: Date.current,
      status: "active",
      payment_type: "expense"
    )

    pending = sp.scheduled_payment_entries.create!(scheduled_date: Date.current, status: "pending")

    assert_no_difference -> { Entry.count } do
      post reject_entry_scheduled_payment_url(sp), params: { entry_id: pending.id, reason: "Not needed" }
    end
    assert_redirected_to scheduled_payments_url

    pending.reload
    assert_equal "rejected", pending.status
    assert_equal "Not needed", pending.rejection_reason
  end
end
