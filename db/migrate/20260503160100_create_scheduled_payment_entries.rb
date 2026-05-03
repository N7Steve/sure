class CreateScheduledPaymentEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduled_payment_entries, id: :uuid do |t|
      t.references :scheduled_payment, null: false, foreign_key: true, type: :uuid
      t.references :entry, foreign_key: true, type: :uuid
      t.references :transfer_entry, foreign_key: { to_table: :entries }, type: :uuid

      t.date :scheduled_date, null: false
      t.string :status, null: false, default: "pending"
      t.text :rejection_reason

      t.timestamps
    end

    add_index :scheduled_payment_entries, [:scheduled_payment_id, :scheduled_date], unique: true, name: "index_sp_entries_on_sp_and_date"
    add_index :scheduled_payment_entries, [:status, :scheduled_date]
  end
end
