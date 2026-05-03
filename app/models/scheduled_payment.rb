class ScheduledPayment < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  belongs_to :target_account, class_name: "Account", optional: true

  has_many :scheduled_payment_entries, dependent: :destroy

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
end
