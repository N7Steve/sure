require "application_system_test_case"

class GoogleDriveExportScheduleFormTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    sign_in @user
    GoogleDriveConnection.create!(
      family: @user.family,
      user: @user,
      google_subject: "schedule-form-system-test",
      email: "drive-form@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: 1.hour.from_now,
      connected_at: Time.current
    )
  end

  test "shows only the fields relevant to the selected range and frequency" do
    visit new_google_drive_export_schedule_url

    fixed_start = find("[data-date-range='fixed_start']", visible: :all)
    rolling_days = find("[data-date-range='rolling_days']", visible: :all)
    weekday = find("[data-frequency='weekly']", visible: :all)
    day_of_month = find("[data-frequency='monthly']", visible: :all)

    assert_not fixed_start.visible?
    assert_not rolling_days.visible?
    assert_not weekday.visible?
    assert_not day_of_month.visible?

    transaction_fields = all("[data-google-drive-export-form-target='transactionField']", visible: :all)
    assert_equal 3, transaction_fields.size
    assert transaction_fields.all?(&:visible?)

    select I18n.t("google_drive_export_schedules.form.export_formats.snapshot"),
           from: I18n.t("google_drive_export_schedules.form.export_format")
    assert transaction_fields.none?(&:visible?)

    select I18n.t("google_drive_export_schedules.form.export_formats.clean"),
           from: I18n.t("google_drive_export_schedules.form.export_format")
    assert transaction_fields.all?(&:visible?)

    select I18n.t("google_drive_export_schedules.form.date_ranges.fixed_start"),
           from: I18n.t("google_drive_export_schedules.form.date_range")
    assert fixed_start.visible?
    assert_not rolling_days.visible?

    select I18n.t("family_exports.google_drive.frequencies.weekly"),
           from: I18n.t("google_drive_export_schedules.form.frequency")
    assert weekday.visible?
    assert_not day_of_month.visible?

    browser_timezone = page.evaluate_script("Intl.DateTimeFormat().resolvedOptions().timeZone")
    timezone_input = find("input[name='google_drive_export_schedule[timezone]']", visible: :all)
    assert_equal browser_timezone, timezone_input.value
  end
end
