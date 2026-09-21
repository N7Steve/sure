class AddForecastBehaviorToTransactions < ActiveRecord::Migration[8.1]
  def up
    add_column :transactions, :forecast_behavior, :string, default: "normal", null: false
    add_index :transactions, :forecast_behavior
    add_check_constraint :transactions,
                         "forecast_behavior IN ('normal', 'exceptional_once', 'irregular_recurring')",
                         name: "transactions_forecast_behavior"

    execute <<~SQL.squish
      UPDATE transactions
      SET forecast_behavior = 'exceptional_once'
      WHERE kind = 'one_time'
    SQL
  end

  def down
    remove_check_constraint :transactions, name: "transactions_forecast_behavior"
    remove_index :transactions, :forecast_behavior
    remove_column :transactions, :forecast_behavior
  end
end
