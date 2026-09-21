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
    account_ids = investment_account_ids

    result = totals_query(account_ids: account_ids, date_range: period.date_range)

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
  #
  # Memoized: top_holdings, allocation, unrealized_gains, unrealized_gains_trend,
  # and day_change each call this, so an unmemoized version ran the same
  # DISTINCT ON query up to 5x per dashboard/report request.
  def current_holdings
    @current_holdings ||= Holding::CurrentForInvestmentAccounts
      .new(investment_account_ids)
      .relation
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

  def period_return_trend(period: Period.current_month)
    currency = family.currency
    account_ids = investment_account_ids
    return nil if account_ids.empty?

    absolute_return = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT COALESCE(SUM(b.net_market_flows * COALESCE(er.rate, 1)), 0)
          FROM balances b
          JOIN accounts a ON a.id = b.account_id
          LEFT JOIN exchange_rates er ON (
            er.date = b.date
            AND er.from_currency = b.currency
            AND er.to_currency = :currency
          )
          WHERE a.id IN (:account_ids)
            AND a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND b.date BETWEEN :start_date AND :end_date
        SQL
        {
          currency: currency,
          account_ids: account_ids,
          family_id: family.id,
          start_date: period.date_range.begin,
          end_date: period.date_range.end
        }
      ])
    ).to_d

    period_start = period.date_range.begin

    # Single query for all accounts' most recent pre-period balance (strict < to avoid
    # double-counting the first day's net_market_flows in both the denominator and absolute_return).
    # FX conversion is done in SQL (matching absolute_return) so balance rows whose currency
    # differs from the account's current currency (e.g. after a currency change) are still picked up.
    start_value = ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish,
          SELECT COALESCE(SUM(b.end_balance * COALESCE(er.rate, 1)), 0)
          FROM accounts a
          INNER JOIN balances b ON b.account_id = a.id
          LEFT JOIN exchange_rates er ON (
            er.date = :period_start
            AND er.from_currency = b.currency
            AND er.to_currency = :currency
          )
          INNER JOIN (
            SELECT b2.account_id, MAX(b2.date) AS max_date
            FROM balances b2
            WHERE b2.account_id IN (:account_ids)
              AND b2.date < :period_start
            GROUP BY b2.account_id
          ) latest ON latest.account_id = b.account_id AND b.date = latest.max_date
          WHERE a.id IN (:account_ids)
            AND a.family_id = :family_id
            AND a.status IN ('draft', 'active')
        SQL
        { account_ids: account_ids, period_start: period_start, family_id: family.id, currency: currency }
      ])
    ).to_d

    return nil if start_value.zero?

    Trend.new(
      current: Money.new(start_value + absolute_return, currency),
      previous: Money.new(start_value, currency)
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
      scope = family.accounts.visible.included_in_reports.where(accountable_type: %w[Investment Crypto])
      scope = scope.included_in_finances_for(user) if user
      scope
    end
  end

  # --- ROBOADVISOR / MANAGED FUND SUPPORT ---

  def roboadvisor_accounts
    @roboadvisor_accounts ||= investment_accounts
      .includes(:accountable, account_providers: :provider)
      .select(&:managed_portfolio?)
  end

  def traditional_investment_accounts
    @traditional_investment_accounts ||= investment_accounts
      .includes(:accountable, :account_providers)
      .reject(&:managed_portfolio?)
  end

  def roboadvisor_portfolio_value
    roboadvisor_accounts.sum { |a| convert_to_family_currency(a.balance, a.currency) }
  end

  def roboadvisor_portfolio_value_money
    Money.new(roboadvisor_portfolio_value, family.currency)
  end

  # Contributions minus withdrawals. Both directions matter: ignoring
  # withdrawals overstates invested capital and understates lifetime return.
  def roboadvisor_net_contributions(period: Period.all_time)
    flows = roboadvisor_transfer_flows(period:)
    flows[:contributions] - flows[:withdrawals]
  end

  def roboadvisor_net_contributions_money
    Money.new(roboadvisor_net_contributions(period: Period.all_time), family.currency)
  end

  def roboadvisor_period_contributions(period: Period.current_month)
    Money.new(roboadvisor_transfer_flows(period:)[:contributions], family.currency)
  end

  def roboadvisor_period_withdrawals(period: Period.current_month)
    Money.new(roboadvisor_transfer_flows(period:)[:withdrawals], family.currency)
  end

  def roboadvisor_total_return
    roboadvisor_accounts.sum { |account| roboadvisor_account_total_return(account) }
  end

  def roboadvisor_total_return_trend
    current = roboadvisor_portfolio_value
    total_return = roboadvisor_total_return
    return nil if total_return.zero? && current.zero?

    Trend.new(
      current: Money.new(current, family.currency),
      previous: Money.new(current - total_return, family.currency)
    )
  end

  # Total inflow transfers (contributions) to a single managed account, all-time.
  def roboadvisor_account_contributions(account)
    roboadvisor_transfer_flows(period: Period.all_time, account_ids: [ account.id ])[:contributions]
  end

  # Return trend for a single managed account. The previous value is an
  # implied capital basis so Trend.value remains the provider/balance P&L.
  def roboadvisor_account_return_trend(account)
    current = convert_to_family_currency(account.balance, account.currency)
    total_return = roboadvisor_account_total_return(account)
    return nil if total_return.zero? && current.zero?

    Trend.new(
      current: Money.new(current, family.currency),
      previous: Money.new(current - total_return, family.currency)
    )
  end

  # Provider-native or balance-derived market P&L. Roboadvisor returns are
  # valuation changes, not merely the non-transfer transactions in the account.
  def roboadvisor_period_return(period: Period.current_month)
    total = roboadvisor_accounts.sum do |account|
      performance = roboadvisor_performance(account)
      profit_loss = performance.profit_loss_for(period.date_range)
      if profit_loss.nil?
        roboadvisor_transaction_return(account, period:)
      else
        convert_to_family_currency(profit_loss, account.currency)
      end
    end
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

      key = [ outflow_acc.id, inflow_acc.id ]
      grouped[key] ||= { outflow_account: outflow_acc, inflow_account: inflow_acc, amount: 0, count: 0 }
      grouped[key][:amount] += amount
      grouped[key][:count] += 1
    end.values.map do |data|
      data.merge(amount: Money.new(data[:amount], family.currency))
    end.sort_by { |item| -item[:amount].amount }
  end

  private
    def roboadvisor_performance(account)
      @roboadvisor_performances ||= {}
      @roboadvisor_performances[account.id] ||= Investment::RoboadvisorPerformance.new(account)
    end

    def roboadvisor_account_total_return(account)
      profit_loss = roboadvisor_performance(account).total_profit_loss
      return convert_to_family_currency(profit_loss, account.currency) unless profit_loss.nil?

      flows = roboadvisor_transfer_flows(period: Period.all_time, account_ids: [ account.id ])
      current = convert_to_family_currency(account.balance, account.currency)
      current + flows[:withdrawals] - flows[:contributions]
    end

    def roboadvisor_transfer_flows(period:, account_ids: nil)
      account_ids ||= roboadvisor_accounts.map(&:id)
      return { contributions: 0.to_d, withdrawals: 0.to_d } if account_ids.empty?

      entries = family.entries
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
        .where(account_id: account_ids, excluded: false, date: period.date_range)
        .where(transactions: { kind: Transaction::TRANSFER_KINDS })

      entries.each_with_object({ contributions: 0.to_d, withdrawals: 0.to_d }) do |entry, totals|
        value = convert_to_family_currency(entry.amount.abs, entry.currency)
        key = entry.amount.negative? ? :contributions : :withdrawals
        totals[key] += value
      end
    end

    def roboadvisor_transaction_return(account, period:)
      entries = account.entries
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
        .where(excluded: false, date: period.date_range)
        .where.not(transactions: { kind: Transaction::TRANSFER_KINDS })
        .where(transactions: { investment_activity_label: Investment::RoboadvisorPerformance::RETURN_ACTIVITY_LABELS })

      entries.sum { |entry| convert_to_family_currency(-entry.amount, entry.currency) }
    end

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

    def totals_query(account_ids:, date_range:)
      if account_ids.empty?
        return Totals.new(family, account_ids: account_ids, date_range: date_range).call
      end

      account_ids_hash = Digest::MD5.hexdigest(account_ids.sort.join(","))

      Rails.cache.fetch([
        "investment_statement", "totals_query", family.id, user&.id,
        account_ids_hash, date_range.begin, date_range.end, family.entries_cache_version
      ]) { Totals.new(family, account_ids: account_ids, date_range: date_range).call }
    end

    def monetizable_currency
      family.currency
    end
end
