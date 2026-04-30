require "digest/md5"

class InvestmentStatement
  include Monetizable

  monetize :total_contributions, :total_dividends, :total_interest, :unrealized_gains

  attr_reader :family, :user

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  # Get totals for a specific period
  def totals(period: Period.current_month)
    trades_in_period = family.trades
      .joins(:entry)
      .where(entries: { date: period.date_range, account_id: investment_account_ids })

    result = totals_query(trades_scope: trades_in_period)

    PeriodTotals.new(
      contributions: Money.new(result[:contributions], family.currency),
      withdrawals: Money.new(result[:withdrawals], family.currency),
      dividends: Money.new(result[:dividends], family.currency),
      interest: Money.new(result[:interest], family.currency),
      trades_count: result[:trades_count],
      currency: family.currency
    )
  end

  # Net contributions (contributions - withdrawals)
  def net_contributions(period: Period.current_month)
    t = totals(period: period)
    t.contributions - t.withdrawals
  end

  # Total portfolio value across all investment accounts
  def portfolio_value
    investment_accounts.sum { |a| convert_to_family_currency(a.balance, a.currency) }
  end

  def portfolio_value_money
    Money.new(portfolio_value, family.currency)
  end

  # Total cash in investment accounts
  def cash_balance
    investment_accounts.sum { |a| convert_to_family_currency(a.cash_balance, a.currency) }
  end

  def cash_balance_money
    Money.new(cash_balance, family.currency)
  end

  # Total holdings value
  def holdings_value
    portfolio_value - cash_balance
  end

  def holdings_value_money
    Money.new(holdings_value, family.currency)
  end

  # All current holdings across investment accounts. Holdings are returned in
  # their native currency; callers that aggregate across accounts must convert
  # to family currency via convert_to_family_currency.
  def current_holdings
    return Holding.none unless investment_accounts.any?

    # Get the latest holding for each security per account
    Holding
      .where(account_id: investment_account_ids)
      .where.not(qty: 0)
      .where(
        id: Holding
          .where(account_id: investment_account_ids)
          .select("DISTINCT ON (holdings.account_id, holdings.security_id) holdings.id")
          .order(Arel.sql("holdings.account_id, holdings.security_id, holdings.date DESC"))
      )
      .includes(:security, :account)
  end

  # Top holdings by family-currency value
  def top_holdings(limit: 5)
    current_holdings
      .to_a
      .sort_by { |h| -convert_to_family_currency(h.amount, h.currency) }
      .first(limit)
  end

  # Portfolio allocation by security. Weights and amounts are computed in the
  # family's currency so cross-currency holdings compare correctly.
  def allocation
    converted = current_holdings.to_a.map do |holding|
      [ holding, convert_to_family_currency(holding.amount, holding.currency) ]
    end

    total = converted.sum { |_, value| value }
    return [] if total.zero?

    converted
      .sort_by { |_, value| -value }
      .map do |holding, value|
        HoldingAllocation.new(
          security: holding.security,
          amount: Money.new(value, family.currency),
          weight: (value / total * 100).round(2),
          trend: holding.trend
        )
      end
  end

  # Unrealized gains across all holdings, summed in family currency
  def unrealized_gains
    current_holdings.sum do |holding|
      trend = holding.trend
      trend ? convert_to_family_currency(trend.value, holding.currency) : 0
    end
  end

  # Total contributions (all time) - returns numeric for monetize
  def total_contributions
    all_time_totals.contributions&.amount || 0
  end

  # Total dividends (all time) - returns numeric for monetize
  def total_dividends
    all_time_totals.dividends&.amount || 0
  end

  # Total interest (all time) - returns numeric for monetize
  def total_interest
    all_time_totals.interest&.amount || 0
  end

  def unrealized_gains_trend
    holdings = current_holdings.to_a
    return nil if holdings.empty?

    # Only include holdings with known cost basis in the calculation
    holdings_with_cost_basis = holdings.select(&:avg_cost)
    return nil if holdings_with_cost_basis.empty?

    current = holdings_with_cost_basis.sum do |h|
      convert_to_family_currency(h.amount, h.currency)
    end
    previous = holdings_with_cost_basis.sum do |h|
      convert_to_family_currency(h.qty * h.avg_cost.amount, h.currency)
    end

    Trend.new(
      current: Money.new(current, family.currency),
      previous: Money.new(previous, family.currency)
    )
  end

  # Day change across portfolio, summed in family currency
  def day_change
    changes = current_holdings.to_a.filter_map do |h|
      t = h.day_change
      next nil unless t
      curr = t.current.is_a?(Money) ? t.current.amount : t.current
      prev = t.previous.is_a?(Money) ? t.previous.amount : t.previous
      [
        convert_to_family_currency(curr, h.currency),
        convert_to_family_currency(prev, h.currency)
      ]
    end

    return nil if changes.empty?

    Trend.new(
      current: Money.new(changes.sum { |c, _| c }, family.currency),
      previous: Money.new(changes.sum { |_, p| p }, family.currency)
    )
  end

  def investment_accounts
    @investment_accounts ||= begin
      scope = family.accounts.visible.where(accountable_type: %w[Investment Crypto])
      scope = scope.included_in_finances_for(user) if user
      scope
    end
  end

  # --- ROBOADVISOR / MANAGED FUND SUPPORT ---

  def roboadvisor_accounts
    @roboadvisor_accounts ||= investment_accounts.select do |a|
      a.investment? && %w[roboadvisor managed_fund].include?(a.subtype)
    end
  end

  def traditional_investment_accounts
    @traditional_investment_accounts ||= investment_accounts.select do |a|
      (a.investment? && !%w[roboadvisor managed_fund].include?(a.subtype)) || a.crypto?
    end
  end

  def roboadvisor_portfolio_value
    roboadvisor_accounts.sum { |a| convert_to_family_currency(a.balance, a.currency) }
  end

  def roboadvisor_portfolio_value_money
    Money.new(roboadvisor_portfolio_value, family.currency)
  end

  # Sum of all incoming transfers to roboadvisor accounts in the given period.
  # Incoming transfers are Transaction entries with transfer kinds and negative
  # amounts (negative = inflow in this codebase's sign convention).
  # Returns a positive numeric value representing total contributions.
  def roboadvisor_net_contributions(period: Period.all_time)
    account_ids = roboadvisor_accounts.map(&:id)
    return 0 if account_ids.empty?

    entries = family.entries
                    .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                    .where(account_id: account_ids, excluded: false)
                    .where(date: period.date_range)
                    .where(transactions: { kind: Transaction::TRANSFER_KINDS })
                    .where("entries.amount < 0") # negative amount = inflow

    # Sum absolute values (inflows are negative, we want a positive total)
    entries.sum { |e| convert_to_family_currency(e.amount.abs, e.currency) }
  end

  def roboadvisor_net_contributions_money
    Money.new(roboadvisor_net_contributions(period: Period.all_time), family.currency)
  end

  def roboadvisor_period_contributions(period: Period.current_month)
    account_ids = roboadvisor_accounts.map(&:id)
    return Money.new(0, family.currency) if account_ids.empty?

    # Incoming transfers = negative amount entries with transfer kinds
    entries = family.entries
                    .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                    .where(account_id: account_ids, excluded: false)
                    .where(date: period.date_range)
                    .where(transactions: { kind: Transaction::TRANSFER_KINDS })
                    .where("entries.amount < 0")

    total = entries.sum { |e| convert_to_family_currency(e.amount.abs, e.currency) }
    Money.new(total, family.currency)
  end

  def roboadvisor_total_return
    roboadvisor_portfolio_value - roboadvisor_net_contributions(period: Period.all_time)
  end

  def roboadvisor_total_return_trend
    contributions = roboadvisor_net_contributions(period: Period.all_time)
    current = roboadvisor_portfolio_value
    return nil if contributions.zero? && current.zero?

    # Trend.value  = current - previous = portfolio_value - contributions = total return
    # Trend.percent = (current - previous) / previous * 100 = return %
    Trend.new(
      current: Money.new(current, family.currency),
      previous: Money.new(contributions, family.currency)
    )
  end

  # Period return: net of all non-transfer transactions in roboadvisor accounts.
  # Income entries (negative amount) become positive gains; expense entries
  # (positive amount) become losses. Result is the net gain/loss for the period.
  def roboadvisor_period_return(period: Period.current_month)
    account_ids = roboadvisor_accounts.map(&:id)
    return Money.new(0, family.currency) if account_ids.empty?

    entries = family.entries
                    .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
                    .where(account_id: account_ids, excluded: false)
                    .where(date: period.date_range)
                    .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })

    # Negate sum: income (negative) becomes positive gain, expenses (positive) become losses
    total = entries.sum { |e| convert_to_family_currency(-e.amount, e.currency) }
    Money.new(total, family.currency)
  end

  def roboadvisor_transfers_grouped(period: Period.current_month)
    account_ids = roboadvisor_accounts.map(&:id)
    return [] if account_ids.empty?

    # Find all transfer transactions on roboadvisor accounts in the period
    transactions = Transaction
                    .joins(:entry)
                    .where(entries: { account_id: account_ids, excluded: false })
                    .where(entries: { date: period.date_range })
                    .where(kind: Transaction::TRANSFER_KINDS)
                    .includes(:transfer_as_inflow, :transfer_as_outflow)

    # Collect unique transfers from both sides of the association
    seen_transfer_ids = Set.new
    transfers = []

    transactions.each do |txn|
      t = txn.transfer
      next unless t
      next if seen_transfer_ids.include?(t.id)
      seen_transfer_ids << t.id
      transfers << t
    end

    # Eager load accounts for all found transfers
    Transfer.includes(outflow_transaction: { entry: :account }, inflow_transaction: { entry: :account })
            .where(id: transfers.map(&:id))
            .each_with_object({}) do |transfer, grouped|
      next unless transfer.outflow_transaction && transfer.inflow_transaction
      outflow_acc = transfer.outflow_transaction.entry.account
      inflow_acc = transfer.inflow_transaction.entry.account

      amount = convert_to_family_currency(transfer.outflow_transaction.entry.amount.abs, transfer.outflow_transaction.entry.currency)

      key = [outflow_acc.id, inflow_acc.id]
      grouped[key] ||= { outflow_account: outflow_acc, inflow_account: inflow_acc, amount: 0, count: 0 }
      grouped[key][:amount] += amount
      grouped[key][:count] += 1
    end.values.map do |data|
      data.merge(amount: Money.new(data[:amount], family.currency))
    end.sort_by { |item| -item[:amount].amount }
  end

  private
    # Today's rates for every currency present on the family's investment
    # accounts and their holdings. Mirrors BalanceSheet::AccountTotals#exchange_rates.
    def exchange_rates
      @exchange_rates ||= begin
        account_currencies = investment_accounts.map(&:currency)
        holding_currencies = Holding.where(account_id: investment_account_ids).distinct.pluck(:currency)
        foreign = (account_currencies + holding_currencies)
                    .compact
                    .uniq
                    .reject { |c| c == family.currency }
        ExchangeRate.rates_for(foreign, to: family.currency, date: Date.current)
      end
    end

    # Unwrap Money first because this codebase's Money (lib/money.rb) ignores
    # the currency arg of `Money.new` when the payload is already a Money, and
    # `Money * numeric` preserves the source currency — so multiplying a
    # foreign-currency Money by a rate would FX-scale the amount but keep the
    # wrong currency label, corrupting downstream sums.
    def convert_to_family_currency(amount, from_currency)
      return amount if amount.nil?
      numeric = amount.is_a?(Money) ? amount.amount : amount
      return numeric if from_currency == family.currency
      rate = exchange_rates[from_currency] || 1
      numeric * rate
    end

    def all_time_totals
      @all_time_totals ||= totals(period: Period.all_time)
    end

    PeriodTotals = Data.define(:contributions, :withdrawals, :dividends, :interest, :trades_count, :currency) do
      def net_flow
        contributions - withdrawals
      end

      def total_income
        dividends + interest
      end
    end

    HoldingAllocation = Data.define(:security, :amount, :weight, :trend)

    def investment_account_ids
      @investment_account_ids ||= investment_accounts.pluck(:id)
    end

    def totals_query(trades_scope:)
      sql_hash = Digest::MD5.hexdigest(trades_scope.to_sql)

      Rails.cache.fetch([
        "investment_statement", "totals_query", family.id, user&.id, sql_hash, family.entries_cache_version
      ]) { Totals.new(family, trades_scope: trades_scope).call }
    end

    def monetizable_currency
      family.currency
    end
end
