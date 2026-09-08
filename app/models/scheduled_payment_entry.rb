class ScheduledPaymentEntry < ApplicationRecord
  belongs_to :scheduled_payment
  belongs_to :entry, optional: true
  belongs_to :transfer_entry, class_name: "Entry", optional: true

  enum :status, { pending: "pending", confirmed: "confirmed", rejected: "rejected", skipped: "skipped" }
  validates :scheduled_date, presence: true

  def confirm!(date_override: nil, amount_override: nil)
    with_payment_lock do
      return unless pending? || skipped? || rejected?
      ensure_unlinked!
      if amount_override && (!amount_override.finite? || amount_override.negative?)
        raise ArgumentError, "Amount must be finite and non-negative"
      end
      scheduled_payment.validate!

      if scheduled_payment.transfer?
        create_transfer_entries!(date_override: date_override, amount_override: amount_override)
      else
        create_transaction_entry!(date_override: date_override, amount_override: amount_override)
      end
      update!(status: "confirmed", rejection_reason: nil)
      sync_entries_after_commit([ entry, transfer_entry ].compact)
    end
  end

  def reject!(reason = nil)
    with_payment_lock do
      update!(status: "rejected", rejection_reason: reason) if pending?
    end
  end

  def skip!
    with_payment_lock do
      update!(status: "skipped", rejection_reason: "skipped_by_user") if pending?
    end
  end

  def retract!
    with_payment_lock do
      return unless confirmed?
      entry_to_destroy = entry
      transfer_entry_to_destroy = transfer_entry
      transfer = entry_to_destroy&.entryable&.try(:transfer)

      # Release FK constraints before destroying entries
      update_columns(
        entry_id: nil,
        transfer_entry_id: nil,
        status: "skipped",
        rejection_reason: "retracted_by_user",
        updated_at: Time.current
      )

      if transfer && transfer_entry_to_destroy
        transfer.destroy!
      else
        entry_to_destroy&.destroy!
        transfer_entry_to_destroy&.destroy!
      end
      sync_entries_after_commit([ entry_to_destroy, transfer_entry_to_destroy ].compact)
    end
  end

  def restore!
    with_payment_lock do
      return unless skipped? || rejected?

      if scheduled_date <= Date.current
        confirm!
      else
        restore_future!
      end
    end
  end

  def revert_future!
    with_payment_lock do
      return unless pending? && scheduled_date.future?

      restore_future!
      true
    end
  end

  def purge_pending!
    with_payment_lock do
      return unless pending?

      ensure_unlinked!
      destroy!
      true
    end
  end

  private

  def ensure_unlinked!
    return if entry_id.nil? && transfer_entry_id.nil?

    errors.add(:entry, :invalid)
    raise ActiveRecord::RecordInvalid, self
  end

  def restore_future!
    ensure_unlinked!
    sp = scheduled_payment
    destroy!
    restores_cursor = sp.once? ? scheduled_date == sp.next_run_date : scheduled_date < sp.next_run_date
    if restores_cursor && sp.occurrences_in(scheduled_date..scheduled_date).include?(scheduled_date)
      sp.update!(next_run_date: scheduled_date, status: sp.completed? ? "active" : sp.status)
    end
  end

  # All state transitions lock the series first, then reload the occurrence.
  # A stale request must see a confirmation committed by a previous request.
  def with_payment_lock
    scheduled_payment.with_lock do
      lock!
      yield
    end
  end

  def sync_entries_after_commit(entries)
    ActiveRecord.after_all_transactions_commit do
      entries.uniq(&:account_id).each(&:sync_account_later)
    end
  end

  def create_transaction_entry!(date_override: nil, amount_override: nil)
    sp = scheduled_payment
    effective_amount = amount_override || sp.amount.abs
    amount_value = sp.expense? ? effective_amount.abs : -effective_amount.abs
    effective_date = date_override || scheduled_date

    transaction = Transaction.create!(
      category: sp.category,
      merchant: sp.merchant
    )

    created_entry = sp.account.entries.create!(
      date: effective_date,
      amount: amount_value,
      currency: sp.currency,
      name: sp.title,
      entryable: transaction
    )

    update!(entry: created_entry)

    # Apply scheduled payment tags to the created transaction
    if sp.tags.any?
      created_entry.entryable.tags = sp.tags
      created_entry.entryable.save!
    end
  end

  def create_transfer_entries!(date_override: nil, amount_override: nil)
    sp = scheduled_payment
    effective_amount = (amount_override || sp.amount).abs
    effective_date = date_override || scheduled_date

    outflow_txn = Transaction.create!(
      category: sp.category,
      kind: Transfer.outflow_kind_for(sp.account, sp.target_account)
    )
    outflow_entry = sp.account.entries.create!(
      date: effective_date,
      amount: effective_amount,
      currency: sp.currency,
      name: sp.title,
      entryable: outflow_txn
    )

    inflow_txn = Transaction.create!(
      category: sp.category,
      kind: Transfer.inflow_kind_for(sp.account, sp.target_account)
    )
    inflow_currency = sp.target_account.currency
    converted_amount = Money.new(effective_amount, sp.currency).exchange_to(inflow_currency, date: effective_date).amount
    inflow_amount = -converted_amount

    inflow_entry = sp.target_account.entries.create!(
      date: effective_date,
      amount: inflow_amount,
      currency: inflow_currency,
      name: sp.title,
      entryable: inflow_txn
    )

    Transfer.create!(
      inflow_transaction: inflow_txn,
      outflow_transaction: outflow_txn,
      status: "confirmed"
    )

    update!(entry: outflow_entry, transfer_entry: inflow_entry)

    [ outflow_txn, inflow_txn ].each { |transaction| transaction.tags = sp.tags } if sp.tags.any?
  end
end
