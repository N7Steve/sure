require "test_helper"

class GoogleDriveExportScheduleTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = @user.accessible_accounts.first
    @connection = GoogleDriveConnection.create!(
      family: @family,
      user: @user,
      google_subject: "google-subject-1",
      email: "drive@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: 1.hour.from_now,
      connected_at: Time.current
    )
  end

  test "calculates a daily next run in the configured timezone" do
    schedule = build_schedule(run_at: "06:30", timezone: "Europe/Madrid")

    next_run = schedule.next_occurrence_after(Time.utc(2026, 9, 20, 5, 0))

    assert_equal Time.utc(2026, 9, 21, 4, 30), next_run.utc
  end

  test "clamps monthly schedules to the final day of shorter months" do
    schedule = build_schedule(frequency: :monthly, day_of_month: 31, run_at: "06:00", timezone: "UTC")

    next_run = schedule.next_occurrence_after(Time.utc(2026, 4, 1, 0, 0))

    assert_equal Time.utc(2026, 4, 30, 6, 0), next_run.utc
  end

  test "rejects an account the owner cannot access" do
    schedule = build_schedule(filters: { account_ids: [ SecureRandom.uuid ] })

    assert_not schedule.valid?
    assert schedule.errors.of_kind?(:filters, :invalid_accounts)
  end

  test "resolves a rolling date range on each run" do
    schedule = build_schedule(date_range: :rolling_days, rolling_days: 30)
    end_date = Date.new(2026, 9, 20)

    assert_equal Date.new(2026, 8, 22), schedule.export_start_date(on: end_date)
  end

  private
    def build_schedule(attributes = {})
      GoogleDriveExportSchedule.new({
        family: @family,
        user: @user,
        google_drive_connection: @connection,
        name: "Daily Drive export",
        filename: "transactions.csv",
        frequency: :daily,
        run_at: "06:00",
        timezone: "UTC",
        date_range: :all_history,
        filters: { account_ids: [ @account.id ] },
        next_run_at: 1.day.from_now
      }.merge(attributes))
    end
end
