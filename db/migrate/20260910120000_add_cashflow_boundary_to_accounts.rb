class AddCashflowBoundaryToAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounts, :cashflow_boundary, :boolean, default: false, null: false

    execute <<~SQL.squish
      UPDATE accounts
      SET cashflow_boundary = TRUE,
          exclude_from_reports = TRUE
      WHERE excluded = TRUE
    SQL

    add_check_constraint :accounts,
                         "cashflow_boundary = FALSE OR exclude_from_reports = TRUE",
                         name: "chk_accounts_cashflow_boundary_requires_report_exclusion"
  end

  def down
    remove_check_constraint :accounts, name: "chk_accounts_cashflow_boundary_requires_report_exclusion"
    remove_column :accounts, :cashflow_boundary
  end
end
