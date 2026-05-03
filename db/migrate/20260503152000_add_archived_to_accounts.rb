class AddArchivedToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :archived, :boolean, default: false, null: false
  end
end
