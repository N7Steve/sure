class FixCorruptedTransferOutflowAmounts < ActiveRecord::Migration[7.2]
  def up
    # Find all confirmed SPEs from transfer scheduled payments
    # where the outflow entry (spe.entry) has a NEGATIVE amount (should be positive)
    corrupted_spes = ScheduledPaymentEntry
      .joins(:scheduled_payment, :entry)
      .where(status: "confirmed")
      .where(scheduled_payments: { payment_type: "transfer" })
      .where("entries.amount < 0")

    corrupted_count = corrupted_spes.count
    Rails.logger.info("[FixCorruptedTransferOutflowAmounts] Found #{corrupted_count} corrupted outflow entries")

    return if corrupted_count == 0

    affected_account_ids = Set.new

    corrupted_spes.includes(:entry).find_each do |spe|
      entry = spe.entry
      next unless entry.present? && entry.amount.negative?

      old_amount = entry.amount
      new_amount = entry.amount.abs  # Flip to positive (outflow = expense)

      entry.update_columns(amount: new_amount, updated_at: Time.current)
      affected_account_ids.add(entry.account_id)

      Rails.logger.info(
        "[FixCorruptedTransferOutflowAmounts] Fixed entry #{entry.id}: " \
        "#{old_amount} → #{new_amount} (account: #{entry.account_id})"
      )
    end

    # Trigger balance recalculation for all affected accounts
    Rails.logger.info("[FixCorruptedTransferOutflowAmounts] Recalculating balances for #{affected_account_ids.size} accounts")
    Account.where(id: affected_account_ids.to_a).find_each do |account|
      account.sync_later
    end

    Rails.logger.info("[FixCorruptedTransferOutflowAmounts] Done. Fixed #{corrupted_count} entries.")
  end

  def down
    # This migration fixes data corruption. Reversing it would re-corrupt the data.
    raise ActiveRecord::IrreversibleMigration
  end
end
