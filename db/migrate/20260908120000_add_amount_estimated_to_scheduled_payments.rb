class AddAmountEstimatedToScheduledPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_payments, :amount_estimated, :boolean, default: false, null: false
  end
end
