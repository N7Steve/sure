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
    assert_includes response.body, I18n.t("scheduled_payments.agenda.title")
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

  test "create supports one-time movements and estimated amounts" do
    future_date = 2.months.from_now.to_date

    assert_difference -> { ScheduledPayment.count }, 1 do
      post scheduled_payments_url, params: {
        scheduled_payment: payment_attributes.merge(
          title: "Estimated tax", amount: 325, frequency: "once",
          start_date: future_date, end_date: future_date + 1.month, amount_estimated: true
        )
      }
    end

    payment = ScheduledPayment.order(:created_at).last
    assert_redirected_to scheduled_payments_url
    assert_predicate payment, :once?
    assert_predicate payment, :amount_estimated?
    assert_equal future_date, payment.next_run_date
    assert_nil payment.end_date
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

  test "new payment opens as a modal without a page heading" do
    get new_scheduled_payment_path, headers: { "Turbo-Frame" => "modal" }
    assert_response :success
    assert_select "h1", count: 0
    assert_select "[role=dialog]", count: 1
    assert_select "turbo-frame#modal", count: 1
    assert_select "form[action=?]", scheduled_payments_path, count: 1
  end

  test "edit payment opens in the modal frame" do
    payment = create_payment
    get edit_scheduled_payment_path(payment), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "h1", count: 0
    assert_select "[role=dialog]", count: 1
    assert_select "turbo-frame#modal", count: 1
    assert_select "form[action=?]", scheduled_payment_path(payment), count: 1
  end

  test "read-only account access cannot modify or confirm a schedule" do
    payment = create_payment(account: accounts(:credit_card))
    occurrence = payment.scheduled_payment_entries.create!(scheduled_date: Date.current)
    sign_in users(:family_member)

    patch scheduled_payment_url(payment), params: { scheduled_payment: { title: "Changed" } }
    assert_response :not_found

    assert_no_difference "Entry.count" do
      post confirm_entry_scheduled_payment_url(payment), params: { entry_id: occurrence.id }
      assert_response :not_found
    end
    assert_equal "Controller robustness payment", payment.reload.title
  end

  test "read-only transfer destination blocks confirmation and transaction retraction" do
    payment = create_payment(payment_type: "transfer", target_account: accounts(:credit_card))
    occurrence = payment.confirm_on!(Date.current)
    sign_in users(:family_member)

    assert_no_difference "Entry.count" do
      post confirm_scheduled_date_scheduled_payment_url(payment), params: { scheduled_date: Date.current }
      assert_response :not_found
      post retract_scheduled_transaction_url(occurrence.entry)
      assert_response :not_found
    end
    assert_predicate occurrence.reload, :confirmed?
  end

  test "create rejects a foreign account before writing the schedule" do
    foreign_account = families(:empty).accounts.create!(name: "Foreign", balance: 0, currency: "USD", accountable: Depository.new)

    assert_no_difference "ScheduledPayment.count" do
      post scheduled_payments_url, params: { scheduled_payment: payment_attributes.merge(account_id: foreign_account.id) }
      assert_response :not_found
    end
  end

  test "update rejects foreign tags without changing existing associations" do
    payment = create_payment(tags: [ tags(:one) ])
    foreign_tag = families(:empty).tags.create!(name: "Foreign")

    patch scheduled_payment_url(payment), params: { scheduled_payment: { title: "Changed", tag_ids: [ foreign_tag.id ] } }

    assert_response :not_found
    assert_equal [ tags(:one).id ], payment.reload.tag_ids
    assert_equal "Controller robustness payment", payment.title
  end

  test "a validation failure rolls back tag changes" do
    payment = create_payment(tags: [ tags(:one) ])

    patch scheduled_payment_url(payment), params: { scheduled_payment: { title: "", tag_ids: [ tags(:two).id ] } }

    assert_response :unprocessable_entity
    assert_equal "Controller robustness payment", payment.reload.title
    assert_equal [ tags(:one).id ], payment.tag_ids
  end

  test "malformed confirmation input produces an alert without a ledger write" do
    payment = create_payment

    assert_no_difference [ "Entry.count", "ScheduledPaymentEntry.count" ] do
      post confirm_scheduled_date_scheduled_payment_url(payment), params: { scheduled_date: "invalid-date" }
      assert_redirected_to scheduled_payments_url
      assert_equal I18n.t("scheduled_payments.invalid_operation"), flash[:alert]
    end
  end

  test "repeated date confirmation creates only one ledger entry" do
    payment = create_payment

    assert_difference "Entry.count", 1 do
      2.times do
        post confirm_scheduled_date_scheduled_payment_url(payment), params: { scheduled_date: Date.current }
        assert_redirected_to scheduled_payments_url
      end
    end
    assert_equal 1, payment.scheduled_payment_entries.confirmed.count
  end

  test "run now passes the family and user scope to the generator" do
    GenerateScheduledPaymentsJob.expects(:perform_now).with(@family.id, @user.id).returns(0)

    post run_now_scheduled_payments_url

    assert_redirected_to scheduled_payments_url
  end

  test "run now reports partial failures" do
    GenerateScheduledPaymentsJob.expects(:perform_now).with(@family.id, @user.id).returns(1)

    post run_now_scheduled_payments_url

    assert_redirected_to scheduled_payments_url
    assert_equal I18n.t("scheduled_payments.generation_failed", count: 1), flash[:alert]
    assert_nil flash[:notice]
  end

  test "new from the incoming transfer side uses the outgoing account and amount" do
    payment = create_payment(payment_type: "transfer", target_account: accounts(:credit_card))
    occurrence = payment.confirm_on!(Date.current)

    get new_scheduled_payment_url, params: { from_entry_id: occurrence.transfer_entry_id }

    assert_response :success
    prefilled = @controller.view_assigns["scheduled_payment"]
    assert_equal @account.id, prefilled.account_id
    assert_equal accounts(:credit_card).id, prefilled.target_account_id
    assert_equal occurrence.entry.amount.abs, prefilled.amount
  end

  test "completed schedules retain their pending occurrence in Agenda" do
    payment = create_payment(end_date: Date.current)
    payment.generate_pending_entry!
    assert_predicate payment.reload, :completed?

    get scheduled_payments_url, params: { month: Date.current.iso8601 }

    assert_response :success
    assert_includes response.body, payment.title
  end

  test "legacy transactions tab redirects to Agenda preserving the month" do
    get transactions_url, params: { tab: "scheduled", scheduled_month: "2026-08-15" }

    assert_redirected_to scheduled_payments_url(month: "2026-08-01")
  end

  test "overview and calendar do not generate payments on a visit" do
    payment = create_payment

    assert_no_difference [ "Entry.count", "ScheduledPaymentEntry.count" ] do
      %w[overview calendar schedules].each do |view|
        get scheduled_payments_url, params: { view: view }
        assert_response :success
        assert_select "h1", text: I18n.t("scheduled_payments.agenda.title")
        assert_select "nav a[href=?]", scheduled_payments_path, minimum: 1
        assert_includes response.body, payment.title
        assert_select ".translation_missing", count: 0
      end
    end
  end

  test "Agenda uses merchant identity in rows and compact calendar amounts" do
    merchant = merchants(:netflix)
    merchant.update!(logo_url: "https://example.com/stellantis.png")
    payment = create_payment(title: "Stellantis finance", amount: 250, merchant: merchant)

    get scheduled_payments_url
    assert_response :success
    assert_select "##{dom_id(payment, "occurrence_#{Date.current.iso8601}")} img[alt='']", count: 1

    get scheduled_payments_url, params: { view: "calendar" }
    assert_response :success
    calendar_links = css_select("a[title='#{payment.title}']")
    assert_not_empty calendar_links
    calendar_links.each do |link|
      assert link.at_css("img[alt='']")
      assert_match(/250/, link.text)
      assert_no_match(/[–-]/, link.text)
      assert_no_match(/#{Regexp.escape(payment.title)}/, link.text)
      assert_includes link["class"].split, "justify-center"
      assert_includes link["class"].split, "gap-2"
      assert_includes link["class"].split, "bg-info/10"
      assert_includes link["class"].split, "text-info"
    end

    get scheduled_payments_url, params: { view: "schedules" }
    assert_response :success
    assert_select "##{dom_id(payment)} img[alt='']", count: 1
    assert_select ".lg\\:grid-cols-12", minimum: 2
    assert_select ".justify-self-center", text: I18n.t("scheduled_payments.status.active"), count: 1
    %w[payment status amount actions].each do |heading|
      assert_select ".hidden.lg\\:grid", text: /#{Regexp.escape(I18n.t("scheduled_payments.table.#{heading}"))}/
    end
  end

  test "Agenda shows compact monthly and planning metrics with estimated amount markers" do
    payment = create_payment(amount: 1200, frequency: "yearly", amount_estimated: true, category: @category)

    get scheduled_payments_url

    assert_response :success
    %w[active remaining pending monthly_cost annual_cost].each do |metric|
      assert_select "[data-agenda-metric=#{metric}]", count: 1
    end
    assert_select "section[data-agenda-month-summary=true]", count: 1 do
      assert_select "[data-agenda-metric]", count: 3
    end
    assert_select "[data-agenda-metric=monthly_provision]", count: 0
    assert_select "##{dom_id(payment, "occurrence_#{Date.current.iso8601}")}", text: /≈/
    assert_select "details", text: /#{Regexp.escape(I18n.t("scheduled_payments.agenda.category_breakdown"))}/

    get scheduled_payments_url, params: { view: "calendar" }
    assert_response :success
    assert_select "a[title=?]", payment.title, text: /≈/

    get confirm_entry_form_scheduled_payment_url(payment), params: { scheduled_date: Date.current.iso8601 }
    assert_response :success
    assert_select "p", text: I18n.t("scheduled_payments.confirm_modal.estimated_hint")
  end

  test "Agenda separates expenses income and transfers in that order" do
    create_payment(title: "Transfer row", payment_type: "transfer", target_account: accounts(:credit_card))
    create_payment(title: "Income row", payment_type: "income")
    create_payment(title: "Expense row", payment_type: "expense")

    get scheduled_payments_url

    assert_response :success
    groups = css_select("[data-agenda-payment-type]")
    assert_equal %w[expense income transfer], groups.map { |group| group["data-agenda-payment-type"] }
    assert_includes groups[0].text, "Expense row"
    assert_includes groups[1].text, "Income row"
    assert_includes groups[2].text, "Transfer row"
  end

  test "transfer schedules use the transaction table transfer icon" do
    payment = create_payment(payment_type: "transfer", target_account: accounts(:credit_card))

    get scheduled_payments_url
    assert_response :success
    row = css_select("##{dom_id(payment, "occurrence_#{Date.current.iso8601}")}").sole
    assert row.at_css("[role=img][aria-label='#{I18n.t("scheduled_payments.form.payment_types.transfer")}'] svg")
    assert_nil row.at_css("img")

    get scheduled_payments_url, params: { view: "schedules" }
    assert_response :success
    row = css_select("##{dom_id(payment)}").sole
    assert row.at_css("[role=img][aria-label='#{I18n.t("scheduled_payments.form.payment_types.transfer")}'] svg")
    assert_nil row.at_css("img")
  end

  test "new payment link targets the modal frame" do
    get scheduled_payments_url

    assert_response :success
    new_link = css_select("a[data-turbo-frame=modal]").find { |node| node["href"].start_with?(new_scheduled_payment_path) }
    assert new_link
  end

  test "calendar confirmation form and submission retain selected view and month" do
    payment = create_payment
    month = Date.current.beginning_of_month.iso8601
    get confirm_entry_form_scheduled_payment_url(payment), params: {
      scheduled_date: Date.current.iso8601, agenda_view: "calendar", agenda_month: month
    }

    assert_response :success
    assert_select "input[name=confirm_amount]", count: 1
    assert_select "input[name=agenda_view][value=calendar]", count: 1
    assert_select "input[name=agenda_month][value=?]", month, count: 1

    post confirm_scheduled_date_scheduled_payment_url(payment), params: {
      scheduled_date: Date.current.iso8601, confirm_amount: "17.50",
      agenda_view: "calendar", agenda_month: month
    }

    assert_redirected_to scheduled_payments_url(view: "calendar", month: month)
    assert_equal BigDecimal("17.50"), payment.scheduled_payment_entries.sole.entry.amount
  end

  test "read only occurrences have no edit or confirmation links" do
    payment = create_payment(account: accounts(:credit_card))
    sign_in users(:family_member)

    %w[overview calendar schedules].each do |view|
      get scheduled_payments_url, params: { view: view }
      assert_response :success
      assert_includes response.body, payment.title
      assert_select "a[href*=?]", confirm_entry_form_scheduled_payment_path(payment), count: 0
      assert_select "a[href*=?]", edit_scheduled_payment_path(payment), count: 0
      assert_select "form[action*=?]", scheduled_payment_path(payment), count: 0
    end
  end

  test "malformed navigation context returns safely to overview" do
    payment = create_payment
    post skip_scheduled_date_scheduled_payment_url(payment), params: {
      scheduled_date: Date.current.iso8601, agenda_view: "https://example.org", agenda_month: "invalid"
    }

    assert_redirected_to scheduled_payments_url(view: "overview", month: Date.current.beginning_of_month.iso8601)
  end

  private
    def payment_attributes
      {
        account_id: @account.id, title: "Controller robustness payment", amount: 25,
        currency: "USD", start_date: Date.current, frequency: "monthly", payment_type: "expense"
      }
    end

    def create_payment(**attributes)
      @family.scheduled_payments.create!(payment_attributes.merge(next_run_date: Date.current).merge(attributes))
    end
end
