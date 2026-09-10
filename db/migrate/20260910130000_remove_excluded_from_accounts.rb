class RemoveExcludedFromAccounts < ActiveRecord::Migration[8.1]
  def change
    remove_column :accounts, :excluded, :boolean, default: false, null: false
  end
end
