class CreateGoogleDriveExports < ActiveRecord::Migration[8.1]
  def change
    create_table :google_drive_connections, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :google_subject, null: false
      t.text :email, null: false
      t.text :access_token
      t.text :refresh_token, null: false
      t.datetime :token_expires_at
      t.string :scopes, null: false, default: ""
      t.string :status, null: false, default: "connected"
      t.datetime :connected_at, null: false
      t.timestamps

      t.index [ :family_id, :google_subject ]
    end

    create_table :google_drive_export_schedules, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :google_drive_connection, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }, index: { name: "idx_drive_export_schedules_connection" }
      t.string :name, null: false, default: "Sure transactions"
      t.string :filename, null: false, default: "sure-transactions.csv"
      t.string :status, null: false, default: "active"
      t.string :frequency, null: false, default: "daily"
      t.time :run_at, null: false, default: "06:00:00"
      t.integer :weekday
      t.integer :day_of_month
      t.string :timezone, null: false, default: "UTC"
      t.string :date_range, null: false, default: "all_history"
      t.date :fixed_start_date
      t.integer :rolling_days
      t.jsonb :filters, null: false, default: {}
      t.datetime :next_run_at, null: false
      t.datetime :last_run_at
      t.datetime :last_success_at
      t.string :last_error_code
      t.timestamps

      t.index [ :status, :next_run_at ], name: "idx_drive_export_schedules_due"
    end

    create_table :google_drive_export_targets, id: :uuid do |t|
      t.references :google_drive_export_schedule, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }, index: { name: "idx_drive_export_targets_schedule" }
      t.string :logical_key, null: false, default: "transactions"
      t.string :provider_file_id
      t.string :web_view_link
      t.string :content_digest
      t.datetime :last_uploaded_at
      t.timestamps

      t.index [ :google_drive_export_schedule_id, :logical_key ], unique: true,
              name: "idx_drive_export_targets_logical_key"
    end

    create_table :google_drive_export_runs, id: :uuid do |t|
      t.references :google_drive_export_schedule, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }, index: { name: "idx_drive_export_runs_schedule" }
      t.references :google_drive_export_target, type: :uuid, null: true,
                   foreign_key: { on_delete: :nullify }, index: { name: "idx_drive_export_runs_target" }
      t.string :status, null: false, default: "pending"
      t.string :triggered_by, null: false, default: "scheduled"
      t.string :result
      t.integer :record_count
      t.string :error_code
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
