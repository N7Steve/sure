class Transactions::BulkDeletionsController < ApplicationController
  def create
    # Exclude split children from bulk delete - they must be deleted via unsplit on parent
    # Only allow deletion from accounts where user has owner or full_control permission
    writable_account_ids = writable_accounts.pluck(:id)

    # Exclude entries linked to scheduled payments - they must be deleted via scheduled payment deletion
    scheduled_entry_ids = ScheduledPaymentEntry.where.not(entry_id: nil).select(:entry_id)
    scheduled_transfer_entry_ids = ScheduledPaymentEntry.where.not(transfer_entry_id: nil).select(:transfer_entry_id)

    entries_scope = Current.family.entries
                      .where(account_id: writable_account_ids)
                      .where(parent_entry_id: nil)
                      .where.not(id: scheduled_entry_ids)
                      .where.not(id: scheduled_transfer_entry_ids)
    destroyed = entries_scope.destroy_by(id: bulk_delete_params[:entry_ids])
    destroyed.map(&:account).uniq.each(&:sync_later)
    redirect_back_or_to transactions_url, notice: "#{destroyed.count} transaction#{destroyed.count == 1 ? "" : "s"} deleted"
  end

  private
    def bulk_delete_params
      params.require(:bulk_delete).permit(entry_ids: [])
    end

    def writable_accounts
      Current.family.accounts.writable_by(Current.user)
    end
end
