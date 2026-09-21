namespace :forecast do
  desc "Backtest wealth forecast V2 (FAMILY_ID/USER_ID required; CASHFLOW_Z optional)"
  task backtest: :environment do
    family = Family.find(ENV.fetch("FAMILY_ID"))
    user = family.users.find(ENV.fetch("USER_ID"))
    cashflow_scenario_z = BigDecimal(
      ENV.fetch("CASHFLOW_Z", ScheduledPayment::WealthForecast::CASHFLOW_SCENARIO_Z.to_s)
    )
    backtest = ScheduledPayment::ForecastBacktest.new(family:, user:, cashflow_scenario_z:)

    puts backtest.limitation
    puts({ cashflow_scenario_z: cashflow_scenario_z.to_f }.to_json)
    backtest.call.each do |result|
      puts({
        model: result.model,
        horizon_months: result.horizon_months,
        samples: result.samples,
        bias: result.bias&.to_f,
        mae: result.mae&.to_f,
        coverage: result.coverage&.to_f
      }.to_json)
    end
  end

  desc "Diagnose monthly residual cashflow inputs (FAMILY_ID and USER_ID required)"
  task diagnose_cashflow: :environment do
    family = Family.find(ENV.fetch("FAMILY_ID"))
    user = family.users.find(ENV.fetch("USER_ID"))
    as_of = ENV["AS_OF"]&.to_date || Date.current
    forecast = ScheduledPayment::WealthForecast.new(family:, user:, as_of:)
    diagnostics = forecast.cashflow_diagnostics

    diagnostics.fetch(:months).each do |month|
      puts({ record_type: "month", **serialize_forecast_diagnostics(month.to_h) }.to_json)
    end
    puts({ record_type: "summary", **serialize_forecast_diagnostics(diagnostics.fetch(:summary)) }.to_json)
  end

  def serialize_forecast_diagnostics(values)
    values.transform_values do |value|
      case value
      when BigDecimal then value.to_f
      when Date then value.iso8601
      else value
      end
    end
  end
end
