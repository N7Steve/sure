class AddCustomOptionsToFamilyExports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_exports, :export_type, :string, null: false, default: "full_backup"
    add_reference :family_exports, :requested_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :family_exports, :start_date, :date
    add_column :family_exports, :end_date, :date
    add_column :family_exports, :filters, :jsonb, null: false, default: {}
    add_column :family_exports, :record_count, :integer

    add_index :family_exports, [ :family_id, :export_type ]
  end
end
