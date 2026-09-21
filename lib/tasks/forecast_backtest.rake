namespace :forecast do
  desc "Backtest wealth forecast V2 against the legacy aggregate trend (FAMILY_ID and USER_ID required)"
  task backtest: :environment do
    family = Family.find(ENV.fetch("FAMILY_ID"))
    user = family.users.find(ENV.fetch("USER_ID"))
    backtest = ScheduledPayment::ForecastBacktest.new(family:, user:)

    puts backtest.limitation
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
end
