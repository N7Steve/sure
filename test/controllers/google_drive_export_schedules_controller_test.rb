require "test_helper"

class GoogleDriveExportSchedulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = @user.accessible_accounts.first
    sign_in @user
    @connection = GoogleDriveConnection.create!(
      family: @family,
      user: @user,
      google_subject: "controller-google-subject",
      email: "controller-drive@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: 1.hour.from_now,
      connected_at: Time.current
    )
  end

  test "creates a schedule and queues its first export" do
    assert_difference("GoogleDriveExportSchedule.count", 1) do
      assert_enqueued_with(job: GoogleDriveExportJob) do
        post google_drive_export_schedules_path, params: {
          google_drive_export_schedule: {
            name: "My automatic export",
            filename: "my-transactions.csv",
            frequency: "daily",
            run_at: "06:30",
            weekday: "1",
            day_of_month: "1",
            timezone: "Europe/Madrid",
            date_range: "all_history",
            filters: { account_ids: [ @account.id ] }
          }
        }
      end
    end

    assert_redirected_to family_exports_path
    schedule = GoogleDriveExportSchedule.order(:created_at).last
    assert_equal @user, schedule.user
    assert_equal @connection, schedule.google_drive_connection
    assert_equal [ @account.id.to_s ], schedule.selected_account_ids.map(&:to_s)
  end

  test "does not allow another user to edit the schedule" do
    schedule = @connection.export_schedules.create!(
      family: @family,
      user: @user,
      filters: { account_ids: [ @account.id ] },
      next_run_at: 1.day.from_now
    )
    other_user = users(:family_member)
    sign_in other_user

    get edit_google_drive_export_schedule_path(schedule)

    assert_redirected_to family_exports_path
  end

  test "requires a connected Drive account" do
    @connection.destroy!

    get new_google_drive_export_schedule_path

    assert_redirected_to family_exports_path
  end

  test "new form exposes only conditional controls and stores timezone in a hidden field" do
    get new_google_drive_export_schedule_path

    assert_response :success
    assert_select "form[data-controller='google-drive-export-form']"
    assert_select "[data-google-drive-export-form-target='dateRangeField'].hidden", count: 2
    assert_select "[data-google-drive-export-form-target='frequencyField'].hidden", count: 2
    assert_select "input[type='hidden'][name='google_drive_export_schedule[timezone]']", count: 1
    assert_select "select[name='google_drive_export_schedule[timezone]']", count: 0
  end
end
