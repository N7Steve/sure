require "test_helper"

class Account::SyncCompleteEventTest < ActiveSupport::TestCase
  test "broadcast refreshes account data without refreshing the page" do
    account = accounts(:depository)

    account.expects(:broadcast_replace_to).with(
      account.family,
      target: "account_#{account.id}",
      partial: "accounts/account",
      locals: { account: account }
    ).once
    account.expects(:broadcast_replace_to).with(
      account.family,
      target: "account-data-refresh-trigger",
      partial: "shared/account_data_refresh"
    ).once
    account.family.expects(:broadcast_sync_complete).once
    account.expects(:broadcast_refresh).never

    Account::SyncCompleteEvent.new(account).broadcast
  end
end
