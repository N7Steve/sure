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
  validates :frequency_day, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :target_account, presence: true, if: :transfer?
  validate :target_account_different_from_source, if: :transfer?

  scope :due_on_or_before, ->(date) { active.where("next_run_date <= ?", date) }
  scope :accessible_by, ->(user) {
    where(account_id: Account.accessible_by(user).select(:id))
  }

  def generate_pending_entry!
    return if end_date.present? && next_run_date > end_date

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
    when "daily"    then from_date + 1.day
    when "weekly"   then from_date + 1.week
    when "biweekly" then from_date + 2.weeks
    when "monthly"  then safe_next_month(from_date, frequency_day)
    when "quarterly" then safe_advance_months(from_date, 3, frequency_day)
    when "yearly"   then safe_advance_months(from_date, 12, frequency_day)
    else
      from_date
    end
  end

  private

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
end
