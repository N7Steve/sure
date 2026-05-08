class ScheduledPaymentEntry < ApplicationRecord
  belongs_to :scheduled_payment
  belongs_to :entry, optional: true
  belongs_to :transfer_entry, class_name: "Entry", optional: true

  enum :status, { pending: "pending", confirmed: "confirmed", rejected: "rejected", skipped: "skipped" }

  def confirm!(date_override: nil, amount_override: nil)
    return unless pending? || skipped? || rejected?

    sp = scheduled_payment
    ActiveRecord::Base.transaction do
      if sp.transfer?
        create_transfer_entries!(date_override: date_override, amount_override: amount_override)
      else
        create_transaction_entry!(date_override: date_override, amount_override: amount_override)
      end
      update!(status: "confirmed")
    end
  end

  def reject!(reason = nil)
    return unless pending?
    update!(status: "rejected", rejection_reason: reason)
  end

  def skip!
    return unless pending?
    update!(status: "skipped")
  end

  def retract!
    return unless confirmed?

    ActiveRecord::Base.transaction do
      entry_to_destroy = entry
      transfer_entry_to_destroy = transfer_entry

      # Release FK constraints before destroying entries
      update_columns(
        entry_id: nil,
        transfer_entry_id: nil,
        status: "skipped",
        rejection_reason: "retracted_by_user",
        updated_at: Time.current
      )

      entry_to_destroy&.destroy!
      transfer_entry_to_destroy&.destroy!
    end
  end

  private

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
    inflow_amount = -effective_amount

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
  end
end
