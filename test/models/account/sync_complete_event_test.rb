require "test_helper"

class Account::SyncCompleteEventTest < ActiveSupport::TestCase
  test "broadcast refreshes the account frame without refreshing the page" do
    account = accounts(:depository)
    trigger_id = ActionView::RecordIdentifier.dom_id(account, :refresh_trigger)

    account.expects(:broadcast_replace_to).with(
      account.family,
      target: "account_#{account.id}",
      partial: "accounts/account",
      locals: { account: account }
    ).once
    account.family.expects(:broadcast_sync_complete).once
    account.expects(:broadcast_replace_to).with(
      account,
      target: trigger_id,
      partial: "shared/frame_refresh",
      locals: { id: trigger_id, url: nil }
    ).once
    account.expects(:broadcast_refresh).never

    Account::SyncCompleteEvent.new(account).broadcast
  end
end
