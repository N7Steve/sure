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
            filters: {
              account_ids: [ @account.id ],
              export_format: "clean",
              include_category: "0",
              include_tags: "1"
            }
          }
        }
      end
    end

    assert_redirected_to family_exports_path
    schedule = GoogleDriveExportSchedule.order(:created_at).last
    assert_equal @user, schedule.user
    assert_equal @connection, schedule.google_drive_connection
    assert_equal [ @account.id.to_s ], schedule.selected_account_ids.map(&:to_s)
    assert schedule.clean_export?
    assert_not schedule.include_category_column?
    assert schedule.include_tags_column?
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

  test "creates a snapshot schedule without transaction-only fields" do
    assert_difference("GoogleDriveExportSchedule.count", 1) do
      post google_drive_export_schedules_path, params: {
        google_drive_export_schedule: {
          name: "Account snapshot",
          filename: "positions.csv",
          frequency: "daily",
          run_at: "06:30",
          timezone: "Europe/Madrid",
          filters: {
            account_ids: [ @account.id ],
            export_format: "snapshot"
          }
        }
      }
    end

    assert_redirected_to family_exports_path
    assert GoogleDriveExportSchedule.order(:created_at).last.snapshot_export?
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
    assert_select "select[name='google_drive_export_schedule[filters][export_format]'] option[selected][value='clean']", count: 1
    assert_select "select[name='google_drive_export_schedule[filters][export_format]'] option[value='snapshot']", count: 1
    assert_select "[data-google-drive-export-form-target='transactionField']", count: 3
    assert_select "input[type='checkbox'][name='google_drive_export_schedule[filters][include_category]'][checked]", count: 1
    assert_select "input[type='checkbox'][name='google_drive_export_schedule[filters][include_tags]'][checked]", count: 1
  end
end
