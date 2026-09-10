class Account::SyncCompleteEvent
  attr_reader :account

  Error = Class.new(StandardError)

  def initialize(account)
    @account = account
  end

  def broadcast
    # Replace account row in accounts list
    account.broadcast_replace_to(
      account.family,
      target: "account_#{account.id}",
      partial: "accounts/account",
      locals: { account: account }
    )

    # Account balances in the application sidebar live outside page-owned
    # frames. Signal each browser to reload its own authorized sidebar after
    # balance materialization has completed.
    account.broadcast_replace_to(
      account.family,
      target: "account-sidebar-refresh-trigger",
      partial: "shared/sidebar_refresh"
    )

    # If this is a manual, unlinked account (i.e. not part of a Plaid Item),
    # trigger the family sync complete broadcast so net worth graph is updated
    unless account.linked?
      account.family.broadcast_sync_complete
    end

    # Ask the browser viewing this account to reload only the account page frame.
    # Rendering that frame in the authenticated browser request preserves user-
    # specific authorization, filters and pagination without morphing the body.
    account.broadcast_replace_to(
      account,
      target: ActionView::RecordIdentifier.dom_id(account, :refresh_trigger),
      partial: "shared/frame_refresh",
      locals: {
        id: ActionView::RecordIdentifier.dom_id(account, :refresh_trigger),
        url: nil
      }
    )
  end
end
