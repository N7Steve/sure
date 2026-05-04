class ScheduledPayment < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  belongs_to :target_account, class_name: "Account", optional: true

  has_many :scheduled_payment_entries, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  monetize :amount

  enum :status, { active: "active", paused: "paused", completed: "completed" }
  enum :frequency, {
    daily: "daily",
    weekly: "weekly",
    biweekly: "biweekly",
    monthly: "monthly",
    quarterly: "quarterly",
    yearly: "yearly"
  }
  enum :payment_type, { expense: "expense", income: "income", transfer: "transfer" }

  validates :title, :amount, :currency, :frequency, :start_date, :next_run_date, presence: true
  validates :frequency_day, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :set_frequency_day_from_start_date, if: -> { start_date.present? }
  before_validation :sync_next_run_date_with_start_date, if: -> { start_date_changed? && !next_run_date_changed? }
  validates :target_account, presence: true, if: :transfer?
  validate :target_account_different_from_source, if: :transfer?
  validate :frequency_day_within_range

  scope :due_on_or_before, ->(date) { active.where("next_run_date <= ?", date) }
  scope :accessible_by, ->(user) {
    where(account_id: Account.accessible_by(user).select(:id))
  }

  def generate_pending_entry!
    return if end_date.present? && next_run_date > end_date

    existing = scheduled_payment_entries.find_by(scheduled_date: next_run_date)

    if existing
      existing.confirm! if auto_confirm && existing.pending?
      return existing
    end

    entry_record = scheduled_payment_entries.create!(
      scheduled_date: next_run_date,
      status: "pending"
    )

    entry_record.confirm! if auto_confirm

    advance_next_run_date!
    entry_record
  end

  def advance_next_run_date!
    new_date = calculate_next_date(next_run_date)

    if end_date.present? && new_date > end_date
      update!(status: "completed", next_run_date: new_date)
    else
      update!(next_run_date: new_date, occurrences_count: occurrences_count + 1)
    end
  end

  def sync_confirmed_entries!
    confirmed_spes = scheduled_payment_entries
      .confirmed
      .includes(:entry, :transfer_entry)

    return if confirmed_spes.empty?

    ActiveRecord::Base.transaction do
      confirmed_spes.each do |spe|
        if spe.entry.present?
          amount_value = expense? ? amount.abs : -amount.abs
          spe.entry.update_columns(name: title, amount: amount_value, currency: currency, updated_at: Time.current)

          if spe.entry.entryable.is_a?(Transaction)
            spe.entry.entryable.update_columns(
              category_id: category_id,
              merchant_id: merchant_id,
              updated_at: Time.current
            )
            # Sync tags (uses association, not update_columns)
            spe.entry.entryable.tags = tags
            spe.entry.entryable.save!
          end
        end

        if spe.transfer_entry.present?
          spe.transfer_entry.update_columns(name: title, updated_at: Time.current)

          if spe.transfer_entry.entryable.is_a?(Transaction)
            spe.transfer_entry.entryable.update_columns(
              category_id: category_id,
              updated_at: Time.current
            )
          end
        end
      end
    end

    # Re-sync account balances for affected accounts
    affected_account_ids = confirmed_spes.flat_map { |spe|
      [spe.entry&.account_id, spe.transfer_entry&.account_id]
    }.compact.uniq

    Account.where(id: affected_account_ids).find_each(&:sync_later)
  end

  def calculate_next_date(from_date)
    case frequency
    when "daily"     then from_date + 1.day
    when "weekly"    then next_weekday_from(from_date, 1)
    when "biweekly"  then next_weekday_from(from_date, 2)
    when "monthly"  then safe_next_month(from_date, frequency_day)
    when "quarterly" then safe_advance_months(from_date, 3, frequency_day)
    when "yearly"   then safe_advance_months(from_date, 12, frequency_day)
    else
      from_date
    end
  end

  def occurrences_in(date_range)
    return [] if start_date.blank?

    occurrences = []
    current = start_date
    iterations = 0
    max_iterations = 10_000

    while current <= date_range.end && iterations < max_iterations
      break if end_date.present? && current > end_date
      occurrences << current if date_range.cover?(current)

      next_date = calculate_next_date(current)
      break if next_date <= current
      current = next_date
      iterations += 1
    end

    occurrences
  end

  # Links existing entries that match this SP's pattern to create confirmed SPEs.
  # Searches by: same name, same account, same merchant, similar amount,
  # and date within ±5 days of any computed occurrence date.
  def link_matching_entries!(user)
    return unless persisted?

    # Build base query: same account, same name, similar amount, same currency
    amount_value = amount.abs
    tolerance = amount_value * 0.05  # 5% tolerance on amount
    min_amount = amount_value - tolerance
    max_amount = amount_value + tolerance

    candidates = family.entries
      .joins(:account)
      .merge(Account.accessible_by(user))
      .where(account_id: account_id)
      .where(currency: currency)
      .where("ABS(amount) BETWEEN ? AND ?", min_amount, max_amount)
      .where("LOWER(name) = LOWER(?)", title)
      .preload(:entryable)

    # If merchant is set, also filter by merchant
    if merchant_id.present?
      candidates = candidates
        .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
        .where(transactions: { merchant_id: merchant_id })
    end

    # For each candidate, check if its date is within ±5 days of any occurrence
    candidates.find_each do |entry|
      # Skip if already linked to any SP
      next if entry.from_scheduled_payment?

      # Compute occurrences in a ±5 day window around the entry date
      search_range = (entry.date - 5.days)..(entry.date + 5.days)
      matching_occurrences = occurrences_in(search_range)

      next if matching_occurrences.empty?

      # Find the nearest occurrence
      nearest_date = matching_occurrences.min_by { |d| (d - entry.date).abs }

      # Create or find an SPE for that occurrence date, link it to this entry
      spe = scheduled_payment_entries.find_or_initialize_by(scheduled_date: nearest_date)
      next if spe.persisted? && spe.confirmed?  # Don't overwrite existing confirmed SPE

      if entry.entryable.is_a?(Transaction) && entry.entryable.transfer.present?
        # For transfers, link both outflow and inflow entries
        transfer = entry.entryable.transfer
        outflow_entry = transfer.outflow_transaction.entry
        inflow_entry = transfer.inflow_transaction.entry
        spe.assign_attributes(
          status: "confirmed",
          entry: outflow_entry,
          transfer_entry: inflow_entry
        )
      else
        spe.assign_attributes(
          status: "confirmed",
          entry: entry
        )
      end

      spe.save!
    end

    # Advance next_run_date past all linked occurrences
    latest_linked = scheduled_payment_entries.confirmed.maximum(:scheduled_date)
    if latest_linked.present?
      next_date = calculate_next_date(latest_linked)
      update!(next_run_date: next_date) if next_date > next_run_date
    end
  end

  private

  def frequency_day_within_range
    return unless frequency.present? && frequency_day.present?

    max = case frequency
          when "weekly", "biweekly" then 6
          when "monthly", "quarterly", "yearly" then 31
          when "daily" then 0
          end

    if max && frequency_day > max
      errors.add(:frequency_day, "must be between 0 and #{max} for #{frequency} frequency")
    end
  end

  def next_weekday_from(from_date, weeks)
    target_wday = frequency_day
    # Find next occurrence of target_wday strictly after from_date
    days_ahead = (target_wday - from_date.wday) % 7
    days_ahead = 7 if days_ahead == 0
    first_occurrence = from_date + days_ahead.days
    # For biweekly, add extra week(s)
    first_occurrence += (weeks - 1).weeks
    first_occurrence
  end

  def safe_next_month(from, day)
    next_m = from.next_month
    Date.new(next_m.year, next_m.month, [day, next_m.end_of_month.day].min)
  end

  def safe_advance_months(from, months, day)
    target = from >> months
    Date.new(target.year, target.month, [day, target.end_of_month.day].min)
  end

  def target_account_different_from_source
    errors.add(:target_account, "must be different from source account") if target_account_id == account_id
  end

  def monetizable_currency
    currency
  end

  def set_frequency_day_from_start_date
    self.frequency_day = case frequency
                         when "daily" then 0
                         when "weekly", "biweekly" then start_date.wday
                         when "monthly", "quarterly", "yearly" then start_date.day
                         else 0
                         end
  end

  def sync_next_run_date_with_start_date
    # Reset next_run_date to match the new start_date
    # If start_date is in the past, the job will catch up and generate entries
    self.next_run_date = start_date
  end
end
