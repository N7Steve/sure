# frozen_string_literal: true

require "test_helper"

class IndexaCapitalItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @item = indexa_capital_items(:configured_with_token)
    @provider = mock("indexa_provider")
    @importer = IndexaCapitalItem::Importer.new(@item, indexa_capital_provider: @provider)
  end

  test "persists complete performance history alongside current balance" do
    performance = {
      return: { index: { "20260731" => 1.0, "20260831" => 1.02 } },
      portfolios: [ { date: "2026-08-31", total_amount: 10_200 } ]
    }
    @provider.expects(:get_account_performance).with(account_number: "NEW12345").returns(performance)
    @provider.expects(:get_account_balance)
      .with(account_number: "NEW12345", performance_data: performance)
      .returns(10_200.to_d)

    @importer.send(:import_account, {
      account_number: "NEW12345", name: "Indexa Capital", currency: "EUR",
      type: "mutual", status: "active"
    }.with_indifferent_access)

    account = @item.indexa_capital_accounts.find_by!(indexa_capital_account_id: "NEW12345")
    assert_equal 10_200.to_d, account.current_balance
    assert_equal 1.02, account.raw_payload.dig("performance_history", "return", "index", "20260831")
  end

  test "keeps previous performance history when Indexa request fails" do
    account = @item.indexa_capital_accounts.create!(
      indexa_capital_account_id: "OLD12345", account_number: "OLD12345",
      name: "Existing Indexa", currency: "EUR", current_balance: 5_000,
      raw_payload: {
        "performance_history" => {
          "return" => { "index" => { "20260831" => 1.02 } }
        }
      }
    )
    @provider.expects(:get_account_performance)
      .with(account_number: "OLD12345")
      .raises(Provider::IndexaCapital::Error.new("temporary failure", :server_error))

    @importer.send(:import_account, {
      account_number: "OLD12345", name: "Existing Indexa", currency: "EUR",
      type: "mutual", status: "active"
    }.with_indifferent_access)

    assert_equal 1.02,
      account.reload.raw_payload.dig("performance_history", "return", "index", "20260831")
    assert_equal 5_000.to_d, account.current_balance
  end
end
