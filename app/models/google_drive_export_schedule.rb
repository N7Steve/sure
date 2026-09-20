class GoogleDriveExportSchedule < ApplicationRecord
  belongs_to :family
  belongs_to :user
  belongs_to :google_drive_connection, inverse_of: :export_schedules

  has_many :targets, class_name: "GoogleDriveExportTarget", dependent: :destroy, inverse_of: :google_drive_export_schedule
  has_many :runs, class_name: "GoogleDriveExportRun", dependent: :destroy, inverse_of: :google_drive_export_schedule

  enum :status, {
    active: "active",
    paused: "paused",
    needs_attention: "needs_attention"
  }, default: :active, validate: true

  enum :frequency, {
    daily: "daily",
    weekly: "weekly",
    monthly: "monthly"
  }, default: :daily, validate: true

  enum :date_range, {
    all_history: "all_history",
    fixed_start: "fixed_start",
    rolling_days: "rolling_days",
    current_year: "current_year"
  }, default: :all_history, validate: true, prefix: true

  validates :name, :filename, :run_at, :timezone, :next_run_at, presence: true
  validates :filename, format: { with: /\.csv\z/i }
  validates :weekday, inclusion: { in: 0..6 }, allow_nil: true
  validates :day_of_month, inclusion: { in: 1..31 }, allow_nil: true
  validates :rolling_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 3_650 }, allow_nil: true
  validate :associations_belong_to_family
  validate :frequency_details_are_present
  validate :date_range_details_are_present
  validate :timezone_is_known
  validate :selected_accounts_are_accessible

  before_validation :normalize_filename
  before_validation :set_default_next_run_at, if: :can_calculate_next_run_at?

  scope :due, -> { active.where("next_run_at <= ?", Time.current) }

  def requested_by
    user
  end

  def selected_account_ids
    filter_values("account_ids")
  end

  def excluded_category_ids
    filter_values("excluded_category_ids")
  end

  def excluded_tag_ids
    filter_values("excluded_tag_ids")
  end

  def export_start_date(on: export_end_date)
    case date_range
    when "all_history" then Date.new(1900, 1, 1)
    when "fixed_start" then fixed_start_date
    when "rolling_days" then on - (rolling_days - 1).days
    when "current_year" then on.beginning_of_year
    end
  end

  def export_end_date
    Time.current.in_time_zone(timezone).to_date
  end

  def next_occurrence_after(moment)
    zone = ActiveSupport::TimeZone[timezone]
    local_moment = moment.in_time_zone(zone)
    hour = run_at.hour
    minute = run_at.min

    candidate_date = case frequency
    when "daily"
      local_moment.to_date
    when "weekly"
      local_moment.to_date + ((weekday - local_moment.wday) % 7).days
    when "monthly"
      date_in_month(local_moment.year, local_moment.month)
    end

    candidate = zone.local(candidate_date.year, candidate_date.month, candidate_date.day, hour, minute)
    return candidate if candidate > moment

    candidate_date = case frequency
    when "daily" then candidate_date + 1.day
    when "weekly" then candidate_date + 1.week
    when "monthly"
      next_month = candidate_date.next_month.beginning_of_month
      date_in_month(next_month.year, next_month.month)
    end

    zone.local(candidate_date.year, candidate_date.month, candidate_date.day, hour, minute)
  end

  private
    def normalize_filename
      return if filename.blank?

      self.filename = "#{filename.sub(/\.csv\z/i, '')}.csv"
    end

    def set_default_next_run_at
      self.next_run_at = next_occurrence_after(Time.current)
    end

    def can_calculate_next_run_at?
      return false unless next_run_at.blank? && run_at.present? && timezone.present?
      return false if weekly? && weekday.blank?
      return false if monthly? && day_of_month.blank?

      ActiveSupport::TimeZone[timezone].present?
    end

    def date_in_month(year, month)
      first = Date.new(year, month, 1)
      first.change(day: [ day_of_month, first.end_of_month.day ].min)
    end

    def associations_belong_to_family
      errors.add(:user, :invalid) if user.present? && family_id.present? && user.family_id != family_id
      if google_drive_connection.present? &&
         (google_drive_connection.family_id != family_id || google_drive_connection.user_id != user_id)
        errors.add(:google_drive_connection, :invalid)
      end
    end

    def frequency_details_are_present
      errors.add(:weekday, :blank) if weekly? && weekday.blank?
      errors.add(:day_of_month, :blank) if monthly? && day_of_month.blank?
    end

    def date_range_details_are_present
      errors.add(:fixed_start_date, :blank) if date_range_fixed_start? && fixed_start_date.blank?
      errors.add(:rolling_days, :blank) if date_range_rolling_days? && rolling_days.blank?
    end

    def timezone_is_known
      errors.add(:timezone, :invalid) if timezone.present? && ActiveSupport::TimeZone[timezone].blank?
    end

    def selected_accounts_are_accessible
      if selected_account_ids.empty?
        errors.add(:filters, :accounts_required)
        return
      end
      return if user.blank?

      selected_ids = selected_account_ids.map(&:to_s)
      accessible_ids = user.accessible_accounts.where(id: selected_ids).pluck(:id).map(&:to_s)
      errors.add(:filters, :invalid_accounts) if (selected_ids - accessible_ids).any?
    end

    def filter_values(key)
      Array(filters&.[](key) || filters&.[](key.to_sym)).compact_blank
    end
end
