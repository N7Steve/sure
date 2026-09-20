require "test_helper"

class DispatchGoogleDriveExportsJobTest < ActiveJob::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = @user.accessible_accounts.first
    @connection = GoogleDriveConnection.create!(
      family: @family,
      user: @user,
      google_subject: "dispatcher-google-subject",
      email: "dispatcher@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: 1.hour.from_now,
      connected_at: Time.current
    )
  end

  test "queues a due schedule once and advances its cursor" do
    schedule = create_schedule(next_run_at: 1.minute.ago)

    assert_enqueued_with(job: GoogleDriveExportJob) do
      DispatchGoogleDriveExportsJob.perform_now
    end

    assert_operator schedule.reload.next_run_at, :>, Time.current
  end

  test "does not queue a paused schedule" do
    create_schedule(next_run_at: 1.minute.ago, status: :paused)

    assert_no_enqueued_jobs only: GoogleDriveExportJob do
      DispatchGoogleDriveExportsJob.perform_now
    end
  end

  private
    def create_schedule(attributes)
      @connection.export_schedules.create!({
        family: @family,
        user: @user,
        filters: { account_ids: [ @account.id ] },
        run_at: "06:00",
        timezone: "UTC"
      }.merge(attributes))
    end
end
