class ScheduledPayment::Agenda
  VIEWS = %w[overview calendar forecast schedules].freeze
  Day = Data.define(:date, :in_month, :occurrences)
  PlanningRow = Data.define(:category, :currency, :monthly_amount, :annual_amount, :amount_estimated)

  attr_reader :family, :user, :month

  def initialize(family:, user:, month: nil)
    @family = family
    @user = user
    @month = self.class.month_from(month)
  end

  def self.month_from(value)
    raw = value.to_s
    raw += "-01" if raw.match?(/\A\d{4}-\d{2}\z/)
    parsed = Date.iso8601(raw).beginning_of_month
    parsed.year.between?(1900, 9998) ? parsed : Date.current.beginning_of_month
  rescue ArgumentError
    Date.current.beginning_of_month
  end

  def payments
    @payments ||= family.scheduled_payments.accessible_by(user)
      .includes(:account, :target_account, :merchant, :category)
      .order(:title, :id).to_a
  end

  def active_count
    payments.count(&:active?)
  end

  def month_occurrences
    @month_occurrences ||= occurrences.select { |occurrence| month_range.cover?(occurrence.scheduled_date) }
  end

  def pending_count
    month_occurrences.count(&:open?)
  end

  # Keep currencies separate: displaying a page must not fetch exchange rates,
  # and summing nominal amounts from different currencies is misleading.
  def remaining_expenses
    remaining = month_occurrences.select { |occurrence| occurrence.open? && occurrence.scheduled_payment.expense? }
    remaining.group_by(&:currency).sort.map do |currency, rows|
      Money.new(rows.sum(&:amount), currency)
    end.presence || [ Money.new(0, family.primary_currency_code) ]
  end

  def recurring_monthly_expenses
    totals_by_currency(planning_expenses, &:monthly_equivalent_amount)
  end

  def recurring_annual_expenses
    totals_by_currency(planning_expenses, &:annualized_amount)
  end

  def planning_breakdown
    @planning_breakdown ||= planning_expenses.group_by { |payment| [ payment.category, payment.currency ] }.map do |(category, currency), rows|
      PlanningRow.new(
        category: category,
        currency: currency,
        monthly_amount: rows.sum(&:monthly_equivalent_amount),
        annual_amount: rows.sum(&:annualized_amount),
        amount_estimated: rows.any?(&:amount_estimated?)
      )
    end.sort_by { |row| [ row.category&.name.to_s, row.currency ] }
  end

  def planning_has_estimates?
    planning_expenses.any?(&:amount_estimated?)
  end

  def older_pending
    @older_pending ||= ScheduledPaymentEntry.where(scheduled_payment_id: payments.map(&:id)).pending
      .where("scheduled_date < ?", [ month, Date.current ].min).order(:scheduled_date).to_a
  end

  def writable?(payment)
    writable_ids.include?(payment.id)
  end

  def days
    @days ||= begin
      by_day = occurrences.group_by(&:scheduled_date)
      grid_range.map { |date| Day.new(date: date, in_month: month_range.cover?(date), occurrences: by_day.fetch(date, [])) }
    end
  end

  def occupied_month_days
    days.select { |day| day.in_month && day.occurrences.any? }
  end

  private

    def month_range
      month..month.end_of_month
    end

    def grid_range
      month.beginning_of_week(:monday)..month.end_of_month.end_of_week(:monday)
    end

    def writable_ids
      @writable_ids ||= begin
        scope = family.scheduled_payments.where(id: payments.map(&:id))
        writable = scope.writable_by(user).pluck(:id)
        # Historical entries can belong to an earlier source/destination.
        # Match the server's ensure_writable_by! without per-row queries.
        restricted_entries = Entry.where.not(account_id: Account.writable_by(user).select(:id)).select(:id)
        linked = ScheduledPaymentEntry.where(scheduled_payment_id: writable)
        restricted_payments = linked.where(entry_id: restricted_entries)
          .or(linked.where(transfer_entry_id: restricted_entries)).distinct.pluck(:scheduled_payment_id)
        (writable - restricted_payments).to_set
      end
    end

    def planning_expenses
      @planning_expenses ||= payments.select { |payment| payment.active? && payment.expense? && payment.recurring? }
    end

    def totals_by_currency(rows)
      rows.group_by(&:currency).sort.map do |currency, currency_rows|
        Money.new(currency_rows.sum { |row| yield(row) }, currency)
      end.presence || [ Money.new(0, family.primary_currency_code) ]
    end

    def occurrences
      @occurrences ||= begin
        stored = ScheduledPaymentEntry.where(scheduled_payment_id: payments.map(&:id), scheduled_date: grid_range)
          .includes(:entry, :transfer_entry).to_a.group_by(&:scheduled_payment_id)
        accessible_account_ids = family.accounts.accessible_by(user).pluck(:id).to_set

        payments.flat_map do |payment|
          records = stored.fetch(payment.id, []).index_by(&:scheduled_date)
          dates = payment.active? ? payment.occurrences_in(grid_range) : []
          (dates | records.keys).filter_map do |date|
            record = records[date]
            # A changed schedule must not reveal historical amounts from an
            # account this viewer can no longer read.
            next if record && [ record.entry, record.transfer_entry ].compact.any? { |entry| !accessible_account_ids.include?(entry.account_id) }

            ScheduledPaymentOccurrence.new(scheduled_payment: payment, scheduled_date: date, entry: record)
          end
        end.sort_by { |occurrence| [ occurrence.scheduled_date, occurrence.scheduled_payment.title, occurrence.scheduled_payment.id ] }
      end
    end
end
