require "test_helper"

class AgendaPrimaryFrontendTest < ActionDispatch::IntegrationTest
  setup do
    @previous_bills_frontend = Rails.configuration.x.bills_frontend_enabled
    Rails.configuration.x.bills_frontend_enabled = false
    sign_in @user = users(:family_admin)
  end

  teardown do
    Rails.configuration.x.bills_frontend_enabled = @previous_bills_frontend
  end

  test "bills and recurring transaction pages redirect to Agenda" do
    get bills_url
    assert_redirected_to scheduled_payments_url

    get recurring_transactions_url
    assert_redirected_to scheduled_payments_url
  end

  test "settings navigation does not expose recurring transactions" do
    get settings_preferences_url

    assert_response :success
    assert_select "a[href=?]", recurring_transactions_path, count: 0
  end

  test "transactions use Agenda without exposing the Bills projection or actions" do
    entry = entries(:transaction)

    get transactions_url
    assert_response :success
    assert_no_match I18n.t("transactions.show.tab_upcoming"), response.body

    get transaction_url(entry)
    assert_response :success
    assert_select "a[href=?]", new_scheduled_payment_path(from_entry_id: entry.id), count: 1
    assert_select "a[href=?]", mark_as_recurring_transaction_path(entry.transaction), count: 0
    assert_select "a[href^='#{new_recurring_transaction_path}']", count: 0

    assert_no_difference "RecurringTransaction.count" do
      post mark_as_recurring_transaction_url(entry.transaction)
    end
    assert_redirected_to scheduled_payments_url
  end

  test "transfer details offer Agenda but not the Bills recurring action" do
    transfer = transfers(:one)
    source_entry = transfer.outflow_transaction.entry

    get transfer_url(transfer)

    assert_response :success
    assert_select "a[href=?]", new_scheduled_payment_path(from_entry_id: source_entry.id), count: 1
    assert_select "a[href=?]", mark_as_recurring_transfer_path(transfer), count: 0

    assert_no_difference "RecurringTransaction.count" do
      post mark_as_recurring_transfer_url(transfer)
    end
    assert_redirected_to scheduled_payments_url
  end

  test "Bills-backed insights stay out of the product frontend" do
    enable_preview_features

    get insights_url

    assert_response :success
    assert_no_match CGI.escapeHTML(insights(:cash_flow_warning).title), response.body
  end

  private
    def enable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end
end
