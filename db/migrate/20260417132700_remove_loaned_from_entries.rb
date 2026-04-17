class RemoveLoanedFromEntries < ActiveRecord::Migration[7.2]
  def change
    remove_column :entries, :loaned, :boolean if column_exists?(:entries, :loaned)
  end
end
