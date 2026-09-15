class Transactions::BulkDeletionsController < ApplicationController
  def create
    # Exclude split children from bulk delete - they must be deleted via unsplit on parent
    # Only allow deletion from accounts where user has owner or full_control permission
    writable_account_ids = writable_accounts.pluck(:id)
    requested_entry_ids = bulk_delete_params[:entry_ids]

    # Exclude entries linked to scheduled payments - they must be deleted via scheduled payment deletion
    protected_entry_ids = ScheduledPaymentEntry
      .where("entry_id IS NOT NULL OR transfer_entry_id IS NOT NULL")
      .pluck(:entry_id, :transfer_entry_id)
      .flatten
      .compact
      .to_set

    entries_scope = Current.family.entries
                      .where(account_id: writable_account_ids)
                      .where(parent_entry_id: nil)
                      .where.not(id: protected_entry_ids)

    selected_entries = entries_scope.where(id: requested_entry_ids).includes(:entryable)
    transfers = selected_entries.filter_map { |entry| entry.transaction&.transfer }.uniq.select do |transfer|
      transfer_entries = [ transfer.outflow_transaction.entry, transfer.inflow_transaction.entry ]
      transfer_entries.all? { |entry| writable_account_ids.include?(entry.account_id) } &&
        transfer_entries.none? { |entry| protected_entry_ids.include?(entry.id) }
    end

    affected_accounts = transfers.flat_map { |transfer| [ transfer.from_account, transfer.to_account ] }
    destroyed_entries = []
    Transfer.transaction do
      destroyed_entries = entries_scope
        .excluding_transfer_transactions
        .destroy_by(id: requested_entry_ids)
      transfers.each(&:destroy!)
    end

    (affected_accounts + destroyed_entries.map(&:account)).compact.uniq.each(&:sync_later)
    destroyed_count = destroyed_entries.count + transfers.count
    redirect_back_or_to transactions_url, notice: "#{destroyed_count} transaction#{destroyed_count == 1 ? "" : "s"} deleted"
  end

  private
    def bulk_delete_params
      params.require(:bulk_delete).permit(entry_ids: [])
    end

    def writable_accounts
      Current.family.accounts.writable_by(Current.user)
    end
end
