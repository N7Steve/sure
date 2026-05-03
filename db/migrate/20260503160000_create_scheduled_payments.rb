class CreateScheduledPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :scheduled_payments, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :category, foreign_key: true, type: :uuid
      t.references :merchant, foreign_key: true, type: :uuid
      t.references :target_account, foreign_key: { to_table: :accounts }, type: :uuid

      t.string :title, null: false
      t.decimal :amount, null: false, precision: 19, scale: 4
      t.string :currency, null: false
      t.string :frequency, null: false
      t.integer :frequency_day, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.date :next_run_date, null: false
      t.string :status, null: false, default: "active"
      t.string :payment_type, null: false, default: "expense"
      t.boolean :auto_confirm, default: false
      t.integer :occurrences_count, default: 0

      t.timestamps
    end

    add_index :scheduled_payments, [:family_id, :status]
    add_index :scheduled_payments, [:next_run_date]
    add_index :scheduled_payments, [:family_id, :next_run_date], where: "status = 'active'"
  end
end
