class ScheduledPaymentEntry < ApplicationRecord
  belongs_to :scheduled_payment
  belongs_to :entry, optional: true
  belongs_to :transfer_entry, class_name: "Entry", optional: true

  enum :status, { pending: "pending", confirmed: "confirmed", rejected: "rejected", skipped: "skipped" }

  def confirm!
    return unless pending?

    sp = scheduled_payment
    ActiveRecord::Base.transaction do
      if sp.transfer?
        create_transfer_entries!
      else
        create_transaction_entry!
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

  private

  def create_transaction_entry!
    sp = scheduled_payment
    amount_value = sp.expense? ? sp.amount.abs : -sp.amount.abs

    transaction = Transaction.create!(
      category: sp.category,
      merchant: sp.merchant
    )

    created_entry = sp.account.entries.create!(
      date: scheduled_date,
      amount: amount_value,
      currency: sp.currency,
      name: sp.title,
      entryable: transaction
    )

    update!(entry: created_entry)
  end

  def create_transfer_entries!
    sp = scheduled_payment

    outflow_txn = Transaction.create!(
      category: sp.category,
      kind: Transfer.outflow_kind_for(sp.account, sp.target_account)
    )
    outflow_entry = sp.account.entries.create!(
      date: scheduled_date,
      amount: sp.amount.abs,
      currency: sp.currency,
      name: sp.title,
      entryable: outflow_txn
    )

    inflow_txn = Transaction.create!(
      category: sp.category,
      kind: Transfer.inflow_kind_for(sp.account, sp.target_account)
    )
    inflow_entry = sp.target_account.entries.create!(
      date: scheduled_date,
      amount: -sp.amount.abs,
      currency: sp.currency,
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
