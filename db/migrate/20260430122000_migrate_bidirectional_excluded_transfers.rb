class MigrateBidirectionalExcludedTransfers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    puts "Starting to migrate bidirectional excluded transfers..."
    
    # Track how many we update
    updated_count = 0

    # Iterate through all transfers
    Transfer.includes(inflow_transaction: { entry: :account }, outflow_transaction: { entry: :account }).find_each do |transfer|
      source_account = transfer.outflow_transaction&.entry&.account
      destination_account = transfer.inflow_transaction&.entry&.account

      # Proceed only if both accounts exist
      if source_account && destination_account
        outflow_kind = Transfer.outflow_kind_for(source_account, destination_account)
        inflow_kind = Transfer.inflow_kind_for(source_account, destination_account)

        # Update if the kinds are different than what's currently there
        if transfer.outflow_transaction.kind != outflow_kind || transfer.inflow_transaction.kind != inflow_kind
          transfer.outflow_transaction.update_columns(kind: outflow_kind)
          transfer.inflow_transaction.update_columns(kind: inflow_kind)
          updated_count += 1
        end
      end
    end

    puts "Successfully updated #{updated_count} transfers."

    # Clear cache to ensure reports reflect changes immediately
    Rails.cache.clear
    puts "Cleared Rails cache."
  end

  def down
    # Downgrading reverts to the old logic where kind_for_account only checked destination
    updated_count = 0

    Transfer.includes(inflow_transaction: { entry: :account }, outflow_transaction: { entry: :account }).find_each do |transfer|
      destination_account = transfer.inflow_transaction&.entry&.account

      if destination_account
        # Old logic equivalent
        old_outflow_kind = if destination_account.excluded?
                             "transfer_to_excluded"
                           elsif destination_account.loan?
                             "loan_payment"
                           elsif destination_account.credit_card? || destination_account.liability?
                             "cc_payment"
                           elsif destination_account.investment? || destination_account.crypto?
                             "investment_contribution"
                           else
                             "funds_movement"
                           end

        old_inflow_kind = "funds_movement"

        if transfer.outflow_transaction.kind != old_outflow_kind || transfer.inflow_transaction.kind != old_inflow_kind
          transfer.outflow_transaction.update_columns(kind: old_outflow_kind)
          transfer.inflow_transaction.update_columns(kind: old_inflow_kind)
          updated_count += 1
        end
      end
    end

    puts "Reverted #{updated_count} transfers to old logic."
    Rails.cache.clear
  end
end
