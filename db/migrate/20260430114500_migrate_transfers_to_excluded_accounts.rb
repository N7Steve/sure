class MigrateTransfersToExcludedAccounts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # Iterate through all transfers to see if the outflow should be marked as "transfer_to_excluded"
    Transfer.includes(inflow_transaction: { entry: :account }, outflow_transaction: :entry).find_each do |t|
      # Proceed only if both inflow/outflow entries and accounts exist
      if t.inflow_transaction&.entry&.account&.excluded?
        t.outflow_transaction&.update_columns(kind: 'transfer_to_excluded')
      end
    end

    # Clear cache to ensure reports reflect changes immediately
    Rails.cache.clear
  end

  def down
    # Downgrading would mean reverting all "transfer_to_excluded" back to their original kind.
    # Since we can't easily know if they were "funds_movement" or "investment_contribution" without checking
    # the destination account type, we revert them based on the destination account.
    Transaction.where(kind: 'transfer_to_excluded').find_each do |transaction|
      # Re-evaluate the kind based on the original logic (without excluded?)
      destination_account = transaction.entryable&.inflow_transaction&.entry&.account
      if destination_account
        new_kind = if destination_account.loan?
                     "loan_payment"
                   elsif destination_account.credit_card? || destination_account.liability?
                     "cc_payment"
                   elsif destination_account.investment? || destination_account.crypto?
                     "investment_contribution"
                   else
                     "funds_movement"
                   end
        transaction.update_columns(kind: new_kind)
      end
    end
  end
end
