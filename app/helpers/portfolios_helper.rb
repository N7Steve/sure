module PortfoliosHelper
  def calculate_estimated_net_liquidity(portfolio_value, total_return)
    portfolio_value_amount = portfolio_value.is_a?(Money) ? portfolio_value.amount : portfolio_value.to_d
    total_return_amount = total_return.is_a?(Money) ? total_return.amount : total_return.to_d

    return portfolio_value if total_return_amount <= 0

    tax = 0.0

    t1_taxable = [total_return_amount, 6_000].min
    tax += t1_taxable * 0.19

    if total_return_amount > 6_000
      t2_taxable = [total_return_amount - 6_000, 44_000].min
      tax += t2_taxable * 0.21
    end

    if total_return_amount > 50_000
      t3_taxable = [total_return_amount - 50_000, 150_000].min
      tax += t3_taxable * 0.23
    end

    if total_return_amount > 200_000
      t4_taxable = [total_return_amount - 200_000, 100_000].min
      tax += t4_taxable * 0.27
    end

    if total_return_amount > 300_000
      t5_taxable = total_return_amount - 300_000
      tax += t5_taxable * 0.28
    end

    net_liquidity_amount = portfolio_value_amount - tax

    if portfolio_value.is_a?(Money)
      subunit_amount = (net_liquidity_amount * portfolio_value.currency.subunit_to_unit).round
      Money.new(subunit_amount, portfolio_value.currency)
    else
      net_liquidity_amount
    end
  end
end
