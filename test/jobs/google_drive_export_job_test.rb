require "test_helper"
require "digest"

class GoogleDriveExportJobTest < ActiveJob::TestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = @user.accessible_accounts.first
    @connection = GoogleDriveConnection.create!(
      family: @family,
      user: @user,
      google_subject: "job-google-subject",
      email: "drive-job@example.com",
      access_token: "access-token",
      refresh_token: "refresh-token",
      token_expires_at: 1.hour.from_now,
      connected_at: Time.current
    )
    @schedule = GoogleDriveExportSchedule.create!(
      family: @family,
      user: @user,
      google_drive_connection: @connection,
      name: "Drive job export",
      filename: "transactions.csv",
      run_at: "06:00",
      timezone: "UTC",
      filters: { account_ids: [ @account.id ] },
      next_run_at: 1.day.from_now
    )
  end

  test "creates the remote file on the first run" do
    drive = mock("google drive")
    GoogleDrive::Client.stubs(:new).with(@connection).returns(drive)
    drive.expects(:find_file).with(schedule_id: @schedule.id, logical_key: "transactions").returns(nil)
    drive.expects(:create_file).with do |attributes|
      attributes[:name] == "transactions.csv" && attributes[:content].include?("transaction_id")
    end.returns({ "id" => "drive-file-1", "webViewLink" => "https://drive.google.com/file/1", "trashed" => false })

    GoogleDriveExportJob.perform_now(@schedule, triggered_by: "initial")

    target = @schedule.targets.find_by!(logical_key: "transactions")
    assert_equal "drive-file-1", target.provider_file_id
    assert_equal "https://drive.google.com/file/1", target.web_view_link
    assert_equal "completed", @schedule.runs.last.status
    assert_equal "uploaded", @schedule.runs.last.result
  end

  test "updates the same remote file after data changes" do
    target = @schedule.targets.create!(
      logical_key: "transactions",
      provider_file_id: "stable-file-id",
      content_digest: "old-digest"
    )
    create_transaction(account: @account, name: "New Drive row", date: Date.current)
    drive = mock("google drive")
    GoogleDrive::Client.stubs(:new).with(@connection).returns(drive)
    drive.expects(:get_file).with(file_id: "stable-file-id").returns(
      {
        "id" => "stable-file-id",
        "name" => "transactions.csv",
        "webViewLink" => "https://drive.google.com/file/stable",
        "trashed" => false
      }
    )
    drive.expects(:update_file).with do |attributes|
      attributes[:file_id] == "stable-file-id" &&
        attributes[:name] == "transactions.csv" &&
        attributes[:content].include?("New Drive row")
    end.returns(
      {
        "id" => "stable-file-id",
        "name" => "transactions.csv",
        "webViewLink" => "https://drive.google.com/file/stable",
        "trashed" => false
      }
    )

    GoogleDriveExportJob.perform_now(@schedule, triggered_by: "manual")

    assert_equal "stable-file-id", target.reload.provider_file_id
    assert_equal "uploaded", @schedule.runs.last.result
  end

  test "does not create a replacement when the stored file is missing" do
    @schedule.targets.create!(logical_key: "transactions", provider_file_id: "missing-file")
    drive = mock("google drive")
    GoogleDrive::Client.stubs(:new).returns(drive)
    drive.expects(:get_file).raises(GoogleDrive::Client::FileMissingError, "missing")
    drive.expects(:create_file).never

    GoogleDriveExportJob.perform_now(@schedule)

    assert_equal "needs_attention", @schedule.reload.status
    assert_equal "file_missing", @schedule.last_error_code
    assert_equal "failed", @schedule.runs.last.status
  end

  test "uploads an account snapshot with the same stable target" do
    @schedule.update!(filters: { account_ids: [ @account.id ], export_format: "snapshot" })
    drive = mock("google drive")
    GoogleDrive::Client.stubs(:new).with(@connection).returns(drive)
    drive.expects(:find_file).with(schedule_id: @schedule.id, logical_key: "transactions").returns(nil)
    drive.expects(:create_file).with do |attributes|
      attributes[:content].start_with?("snapshot_date,position_id,institution,name,type,subtype,scope,value,currency,notes") &&
        attributes[:content].include?(@account.id)
    end.returns({ "id" => "snapshot-file", "webViewLink" => "https://drive.google.com/file/snapshot", "trashed" => false })

    GoogleDriveExportJob.perform_now(@schedule, triggered_by: "initial")

    assert_equal "snapshot-file", @schedule.targets.find_by!(logical_key: "transactions").provider_file_id
    assert_equal "completed", @schedule.runs.last.status
  end

  test "renames the existing file without changing its id" do
    result = Family::TransactionCsvExporter.new(@schedule, schema: :drive).generate
    digest = Digest::SHA256.hexdigest(result.io.read)
    target = @schedule.targets.create!(
      logical_key: "transactions",
      provider_file_id: "stable-file-id",
      content_digest: digest
    )
    drive = mock("google drive")
    GoogleDrive::Client.stubs(:new).with(@connection).returns(drive)
    drive.expects(:get_file).with(file_id: "stable-file-id").returns(
      {
        "id" => "stable-file-id",
        "name" => "old-name.csv",
        "webViewLink" => "https://drive.google.com/file/stable",
        "trashed" => false
      }
    )
    drive.expects(:update_file).with do |attributes|
      attributes[:file_id] == "stable-file-id" && attributes[:name] == "transactions.csv"
    end.returns(
      {
        "id" => "stable-file-id",
        "name" => "transactions.csv",
        "webViewLink" => "https://drive.google.com/file/stable",
        "trashed" => false
      }
    )

    GoogleDriveExportJob.perform_now(@schedule, triggered_by: "manual")

    assert_equal "stable-file-id", target.reload.provider_file_id
    assert_equal "uploaded", @schedule.runs.last.result
  end
end
