class ScheduledPayment < ApplicationRecord
  include Monetizable

  HISTORICAL_DATE_TOLERANCE_DAYS = 5
  FIXED_AMOUNT_TOLERANCE = BigDecimal("0.05")
  ESTIMATED_AMOUNT_TOLERANCE = BigDecimal("0.40")

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  belongs_to :target_account, class_name: "Account", optional: true

  has_many :scheduled_payment_entries, dependent: :destroy
  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  monetize :amount

  enum :status, { active: "active", paused: "paused", completed: "completed" }, validate: true
  enum :frequency, {
    once: "once",
    daily: "daily",
    weekly: "weekly",
    biweekly: "biweekly",
    monthly: "monthly",
    quarterly: "quarterly",
    yearly: "yearly"
  }, validate: true
  enum :payment_type, { expense: "expense", income: "income", transfer: "transfer" }, validate: true

  validates :title, :amount, :currency, :frequency, :start_date, :next_run_date, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0, less_than: Float::INFINITY }
  validates :frequency_day, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :set_frequency_day_from_start_date, if: -> { start_date.present? }
  before_validation :sync_next_run_date_with_start_date, if: :reset_next_run_date?
  before_validation :clear_end_date_for_once, if: :once?
  validates :target_account, presence: true, if: :transfer?
  validate :target_account_different_from_source, if: :transfer?
  validate :frequency_day_within_range
  validate :associations_belong_to_family
  validate :estimated_amount_requires_manual_confirmation
  validates :end_date, comparison: { greater_than_or_equal_to: :start_date }, allow_nil: true, if: -> { start_date.present? }

  scope :due_on_or_before, ->(date) { active.where("next_run_date <= ?", date) }
  scope :accessible_by, ->(user) {
    account_ids = Account.accessible_by(user).select(:id)
    where(account_id: account_ids).where(target_account_id: account_ids).or(
      where(account_id: account_ids, target_account_id: nil)
    )
  }
  scope :writable_by, ->(user) {
    account_ids = Account.writable_by(user).select(:id)
    where(account_id: account_ids).where(target_account_id: account_ids).or(
      where(account_id: account_ids, target_account_id: nil)
    )
  }

  def generate_pending_entry!(through: nil)
    with_lock do
      return unless active?
      if end_date.present? && next_run_date > end_date
        update!(status: "completed")
        return
      end
      return if through.present? && next_run_date > through

      entry_record = scheduled_payment_entries.find_or_initialize_by(scheduled_date: next_run_date)
      new_occurrence = entry_record.new_record?
      entry_record.save! if new_occurrence
      entry_record.confirm! if auto_confirm && entry_record.pending?

      # Recover an existing occurrence too: leaving the cursor behind it makes
      # the catch-up job loop forever. Creation and advancement commit together.
      advance_next_run_date!(count_occurrence: new_occurrence)
      entry_record
    end
  end

  def advance_next_run_date!(count_occurrence: true)
    if once?
      update!(occurrences_count: occurrences_count + (count_occurrence ? 1 : 0), status: "completed")
      return
    end

    new_date = calculate_next_date(next_run_date)
    raise ArgumentError, "Schedule must advance" unless new_date > next_run_date

    update!(next_run_date: new_date,
            occurrences_count: occurrences_count + (count_occurrence ? 1 : 0),
            status: end_date.present? && new_date > end_date ? "completed" : status)
  end

  def confirm_on!(date, **overrides)
    with_lock do
      occurrence = occurrence_for_date!(date)
      new_occurrence = occurrence.new_record?
      occurrence.save! if new_occurrence
      occurrence.confirm!(**overrides)
      advance_next_run_date!(count_occurrence: new_occurrence) if next_run_date == date
      occurrence
    end
  end

  def skip_on!(date)
    with_lock do
      occurrence = occurrence_for_date!(date)
      new_occurrence = occurrence.new_record?
      occurrence.save! if new_occurrence
      occurrence.skip!
      advance_next_run_date!(count_occurrence: new_occurrence) if next_run_date == date
      occurrence
    end
  end

  def ensure_writable_by!(user)
    self.class.where(family_id: user.family_id).writable_by(user).find(id)
    # Editing a series can also annotate or retract historical entries on an
    # account it used before the source/destination was changed.
    linked_entries = Entry.where(id: scheduled_payment_entries.select(:entry_id)).or(
      Entry.where(id: scheduled_payment_entries.select(:transfer_entry_id))
    )
    if linked_entries.where.not(account_id: Account.writable_by(user).select(:id)).exists?
      raise ActiveRecord::RecordNotFound
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
          # Solo sincronizar nombre (no importe, no currency, no fecha)
          spe.entry.update_columns(name: title, updated_at: Time.current)

          if spe.entry.entryable.is_a?(Transaction)
            spe.entry.entryable.update_columns(
              category_id: category_id,
              merchant_id: merchant_id,
              updated_at: Time.current
            )
            # Sync tags
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
            spe.transfer_entry.entryable.tags = tags
          end
        end
      end
    end
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

  def recurring?
    !once?
  end

  def annualized_amount
    amount.abs * occurrences_per_year
  end

  def monthly_equivalent_amount
    annualized_amount / BigDecimal("12")
  end

  def monthly_provision_amount
    case frequency
    when "quarterly" then amount.abs / BigDecimal("3")
    when "yearly" then amount.abs / BigDecimal("12")
    else BigDecimal("0")
    end
  end

  def provisionable?
    expense? && frequency.in?(%w[quarterly yearly])
  end

  def occurrences_in(date_range)
    return [] if start_date.blank?

    occurrences = []
    current = first_occurrence_on_or_after(date_range.begin)
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
  # Searches by: same name, account, category, merchant, tags and currency;
  # compatible amount and date within the historical schedule tolerance.
  def link_matching_entries!(user, source_entry_id: nil)
    return unless persisted?

    with_lock do
      ensure_writable_by!(user)
      source_entry = find_historical_source_entry(user, source_entry_id)
      link_historical_entries!(source_entry: source_entry)
    end
  end

  private

  def link_historical_entries!(source_entry: nil)
    # A future start date controls generation, but must not prevent linking the
    # existing transaction from which the schedule was created or its history.
    amount_value = amount.abs
    tolerance = amount_value * historical_amount_tolerance
    min_amount = amount_value - tolerance
    max_amount = amount_value + tolerance
    expected_tag_ids = tag_ids.map(&:to_s).sort

    candidates = family.entries
      .where(entryable_type: "Transaction")
      .where(account_id: account_id)
      .where("entries.date <= ?", Date.current)
      .where(currency: currency)
      .where("ABS(entries.amount) BETWEEN ? AND ?", min_amount, max_amount)
      .where(income? ? "entries.amount < 0" : "entries.amount >= 0")
      .where("TRIM(LOWER(entries.name)) = TRIM(LOWER(?))", title)
      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
      .where(transactions: { category_id: category_id, merchant_id: merchant_id })
      .preload(entryable: :tags)

    linked_count = 0

    source_result = :not_provided
    if source_entry
      source_entry.with_lock do
        source_result = link_historical_source_entry!(source_entry)
        linked_count += 1 if source_result == :linked
      end
    end

    candidates = candidates.where.not(id: source_entry.id) if source_entry
    candidate_count = candidates.count
    candidates.find_each do |entry|
      entry.with_lock do
        linked_count += 1 if link_historical_entry!(entry, expected_tag_ids: expected_tag_ids)
      end
    end

    # Do not jump over an unpaid gap just because a later charge was linked.
    while active? && scheduled_payment_entries.confirmed.exists?(scheduled_date: next_run_date)
      advance_next_run_date!(count_occurrence: false)
    end

    Rails.logger.info(
      "Scheduled payment historical matching completed: " \
        "payment=#{id} source=#{source_result} candidates=#{candidate_count} linked=#{linked_count}"
    )
    linked_count
  end

  def find_historical_source_entry(user, source_entry_id)
    return if source_entry_id.blank?

    family.entries
      .joins(:account)
      .merge(Account.writable_by(user))
      .where(entryable_type: "Transaction")
      .find(source_entry_id)
  end

  def link_historical_entry!(entry, expected_tag_ids:)
    return false if entry.from_scheduled_payment?
    return false unless entry.account_id == account_id && entry.currency == currency
    correct_direction = income? ? entry.amount.negative? : entry.amount >= 0
    return false unless correct_direction
    return false if entry.entryable.tags.map { |tag| tag.id.to_s }.sort != expected_tag_ids

    transfer = entry.entryable.transfer
    if transfer?
      correct_accounts = transfer &&
        transfer.from_account.id == account_id &&
        transfer.to_account.id == target_account_id
      return false unless correct_accounts
      return false if transfer.inflow_transaction.entry.from_scheduled_payment?
    elsif transfer
      return false
    end

    search_range = (entry.date - HISTORICAL_DATE_TOLERANCE_DAYS.days)..
      (entry.date + HISTORICAL_DATE_TOLERANCE_DAYS.days)
    matching_occurrences = schedule_dates_in(search_range)
    return false if matching_occurrences.empty?

    nearest_date = matching_occurrences.min_by { |date| (date - entry.date).abs }
    scheduled_entry = scheduled_payment_entries.find_or_initialize_by(scheduled_date: nearest_date)
    return false if scheduled_entry.persisted? && !scheduled_entry.pending?

    scheduled_entry.assign_attributes(status: "confirmed", entry: entry, rejection_reason: nil)
    scheduled_entry.transfer_entry = transfer.inflow_transaction.entry if transfer
    scheduled_entry.save!
    true
  end

  # The user explicitly selected this transaction as the source of the
  # schedule. Do not make that deliberate choice pass through the heuristic
  # filters used to discover additional history.
  def link_historical_source_entry!(entry)
    return :already_linked if entry.from_scheduled_payment?

    transfer = entry.entryable.transfer
    transfer_entry = transfer&.inflow_transaction&.entry
    return :already_linked if transfer_entry&.from_scheduled_payment?

    search_range = (entry.date - HISTORICAL_DATE_TOLERANCE_DAYS.days)..
      (entry.date + HISTORICAL_DATE_TOLERANCE_DAYS.days)
    scheduled_date = schedule_dates_in(search_range).min_by { |date| (date - entry.date).abs }
    scheduled_date ||= entry.date

    scheduled_entry = scheduled_payment_entries.find_or_initialize_by(scheduled_date: scheduled_date)
    return :occupied if scheduled_entry.persisted? && !scheduled_entry.pending?

    scheduled_entry.assign_attributes(
      status: "confirmed",
      entry: entry,
      transfer_entry: transfer_entry,
      rejection_reason: nil
    )
    scheduled_entry.save!
    :linked
  end

  def historical_amount_tolerance
    amount_estimated? ? ESTIMATED_AMOUNT_TOLERANCE : FIXED_AMOUNT_TOLERANCE
  end

  def schedule_dates_in(date_range)
    date_range.select { |date| date_on_schedule?(date) }
  end

  def date_on_schedule?(date)
    return false if start_date.blank?
    return false if end_date.present? && date > end_date

    case frequency
    when "once"
      date == start_date
    when "daily"
      true
    when "weekly"
      ((date - start_date).to_i % 7).zero?
    when "biweekly"
      ((date - start_date).to_i % 14).zero?
    when "monthly", "quarterly", "yearly"
      months = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.fetch(frequency)
      month_offset = (date.year - start_date.year) * 12 + date.month - start_date.month
      expected_day = [ frequency_day || start_date.day, date.end_of_month.day ].min

      (month_offset % months).zero? && date.day == expected_day
    else
      false
    end
  end

  def occurrence_for_date!(date)
    existing = scheduled_payment_entries.find_by(scheduled_date: date)
    return existing if existing
    raise ArgumentError, "Date is outside the schedule" unless occurrences_in(date..date).include?(date)

    scheduled_payment_entries.build(scheduled_date: date)
  end

  # Jump to the requested window, so an old daily schedule doesn't exhaust
  # the iteration cap before reaching the month being displayed.
  def first_occurrence_on_or_after(date)
    return start_date if date <= start_date

    current = if (days = { "daily" => 1, "weekly" => 7, "biweekly" => 14 }[frequency])
      start_date + ((date - start_date).to_i / days) * days
    elsif (months = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }[frequency])
      elapsed_months = (date.year - start_date.year) * 12 + date.month - start_date.month
      cycles = elapsed_months / months
      cycles.zero? ? start_date : safe_advance_months(start_date, cycles * months, frequency_day)
    else
      return start_date
    end

    current < date ? calculate_next_date(current) : current
  end

  def occurrences_per_year
    case frequency
    when "daily" then BigDecimal("365.25")
    when "weekly" then BigDecimal("365.25") / BigDecimal("7")
    when "biweekly" then BigDecimal("365.25") / BigDecimal("14")
    when "monthly" then BigDecimal("12")
    when "quarterly" then BigDecimal("4")
    when "yearly" then BigDecimal("1")
    else BigDecimal("0")
    end
  end

  def associations_belong_to_family
    return if family_id.blank?

    { account: account, target_account: target_account, category: category }.each do |attribute, record|
      errors.add(attribute, :invalid) if record && record.family_id != family_id
    end
    if merchant.is_a?(FamilyMerchant) && merchant.family_id != family_id
      errors.add(:merchant, :invalid)
    end
    errors.add(:tags, :invalid) if tags.any? { |tag| tag.family_id != family_id }
  end

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

  def estimated_amount_requires_manual_confirmation
    errors.add(:auto_confirm, :invalid) if amount_estimated? && auto_confirm?
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

  def reset_next_run_date?
    !next_run_date_changed? && (start_date_changed? || (frequency_changed? && once?))
  end

  def clear_end_date_for_once
    self.end_date = nil
  end
end
