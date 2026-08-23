require "test_helper"

class FamilyExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @non_admin = users(:family_member)
    @family = @admin.family

    sign_in @admin
  end

  test "non-admin can access custom exports but not full backups" do
    sign_in @non_admin

    get new_family_export_path
    assert_redirected_to root_path

    post family_exports_path
    assert_redirected_to root_path

    get family_exports_path
    assert_response :success

    get new_family_export_path(export_type: :transactions_csv)
    assert_response :success
    assert_select "h2", text: "Export transactions to CSV"
    assert_select "input[name='family_export[start_date]'][value='#{1.month.ago.to_date.iso8601}']"
    assert_select "input[name='family_export[end_date]'][value='#{Date.current.iso8601}']"
  end

  test "admin can view export modal" do
    get new_family_export_path
    assert_response :success
    assert_select "h2", text: "Export your data"
  end

  test "admin can mark a lost export as failed" do
    export = @family.family_exports.create!
    export.update_columns(status: "processing", updated_at: 2.hours.ago)

    post cancel_family_export_path(export)

    assert_redirected_to family_exports_path
    assert_equal "failed", export.reload.status
  end

  test "cancel refuses an export that is not presumed lost" do
    export = @family.family_exports.create!
    export.update_columns(status: "processing", updated_at: 5.minutes.ago)

    post cancel_family_export_path(export)

    assert_equal I18n.t("family_exports.cancel.not_cancellable"), flash[:alert]
    assert_equal "processing", export.reload.status
  end

  test "non-admin cannot cancel an export" do
    export = @family.family_exports.create!
    export.update_columns(status: "processing", updated_at: 2.hours.ago)

    sign_in @non_admin
    post cancel_family_export_path(export)

    assert_redirected_to root_path
    assert_equal "processing", export.reload.status
  end

  test "admin can create export" do
    assert_enqueued_with(job: FamilyDataExportJob) do
      post family_exports_path
    end

    assert_redirected_to family_exports_path
    assert_equal "Export started. You'll be able to download it shortly.", flash[:notice]

    export = @family.family_exports.last
    assert_equal "pending", export.status
    assert export.full_backup?
    assert_equal @admin, export.requested_by
  end

  test "user can create a filtered transaction CSV export" do
    account = @non_admin.accessible_accounts.first
    category = @family.categories.first
    tag = @family.tags.first
    sign_in @non_admin

    assert_enqueued_with(job: FamilyDataExportJob) do
      post family_exports_path, params: {
        family_export: {
          export_type: "transactions_csv",
          start_date: "2026-01-01",
          end_date: "2026-03-31",
          filters: {
            account_ids: [ account.id ],
            excluded_category_ids: [ category.id ],
            excluded_tag_ids: [ tag.id ]
          }
        }
      }
    end

    assert_redirected_to family_exports_path
    export = @family.family_exports.order(:created_at).last
    assert export.transactions_csv?
    assert_equal @non_admin, export.requested_by
    assert_equal Date.new(2026, 1, 1), export.start_date
    assert_equal Date.new(2026, 3, 31), export.end_date
    assert_equal [ account.id ], export.selected_account_ids
    assert_equal [ category.id ], export.excluded_category_ids
    assert_equal [ tag.id ], export.excluded_tag_ids
  end

  test "custom export rejects accounts the requester cannot access" do
    inaccessible_account = families(:empty).accounts.create!(
      name: "Inaccessible export account",
      balance: 0,
      currency: "USD",
      accountable: Depository.new
    )
    sign_in @non_admin

    assert_no_difference "@family.family_exports.count" do
      assert_no_enqueued_jobs only: FamilyDataExportJob do
        post family_exports_path, params: {
          family_export: {
            export_type: "transactions_csv",
            start_date: "2026-01-01",
            end_date: "2026-03-31",
            filters: { account_ids: [ inaccessible_account.id ] }
          }
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "admin can view export list" do
    export1 = @family.family_exports.create!(status: "completed")
    export2 = @family.family_exports.create!(status: "processing")

    get family_exports_path
    assert_response :success

    assert_match export1.filename, response.body
    assert_match "Exporting...", response.body
    assert_select "h2", text: "Full backup"
    assert_select "h2", text: "Custom transaction export"
  end

  test "member only sees their own custom transaction exports" do
    account = @non_admin.accessible_accounts.first
    own_export = @family.family_exports.create!(
      export_type: :transactions_csv,
      requested_by: @non_admin,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current,
      filters: { account_ids: [ account.id ] }
    )
    backup = @family.family_exports.create!
    other_custom_export = @family.family_exports.create!(
      export_type: :transactions_csv,
      requested_by: @admin,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current,
      filters: { account_ids: [ @admin.accessible_accounts.first.id ] }
    )
    sign_in @non_admin

    get family_exports_path

    assert_response :success
    assert_match own_export.filename, response.body
    assert_no_match backup.filename, response.body
    assert_no_match other_custom_export.filename, response.body
  end

  test "admin can download completed export" do
    export = @family.family_exports.create!(status: "completed")
    export.export_file.attach(
      io: StringIO.new("test zip content"),
      filename: "test.zip",
      content_type: "application/zip"
    )

    get download_family_export_path(export)
    assert_redirected_to(/rails\/active_storage/)
  end

  test "cannot download incomplete export" do
    export = @family.family_exports.create!(status: "processing")

    get download_family_export_path(export)
    assert_redirected_to family_exports_path
    assert_equal "Export not ready for download", flash[:alert]
  end

  test "admin can delete export" do
    export = @family.family_exports.create!(status: "completed")

    assert_difference "@family.family_exports.count", -1 do
      delete family_export_path(export)
    end

    assert_redirected_to family_exports_path
    assert_equal "Export deleted successfully", flash[:notice]
  end

  test "admin can delete export with attached file" do
    export = @family.family_exports.create!(status: "completed")
    export.export_file.attach(
      io: StringIO.new("test zip content"),
      filename: "test.zip",
      content_type: "application/zip"
    )

    assert export.export_file.attached?
    assert_difference "@family.family_exports.count", -1 do
      delete family_export_path(export)
    end

    assert_redirected_to family_exports_path
    assert_equal "Export deleted successfully", flash[:notice]
  end

  test "admin can delete failed export with attached file" do
    export = @family.family_exports.create!(status: "failed")
    export.export_file.attach(
      io: StringIO.new("failed export content"),
      filename: "failed.zip",
      content_type: "application/zip"
    )

    assert export.export_file.attached?
    assert_difference "@family.family_exports.count", -1 do
      delete family_export_path(export)
    end

    assert_redirected_to family_exports_path
    assert_equal "Export deleted successfully", flash[:notice]
  end

  test "export file is purged when export is deleted" do
    export = @family.family_exports.create!(status: "completed")
    export.export_file.attach(
      io: StringIO.new("test zip content"),
      filename: "test.zip",
      content_type: "application/zip"
    )

    # Verify file is attached
    assert export.export_file.attached?
    file_id = export.export_file.id

    # Delete the export
    delete family_export_path(export)

    # Verify the export record is gone
    assert_not FamilyExport.exists?(export.id)

    # Verify the Active Storage attachment is also gone
    # Note: Active Storage purges files asynchronously with `dependent: :purge_later`
    # In tests, we can check that the attachment record is gone
    assert_not ActiveStorage::Attachment.exists?(file_id)
  end

  test "index responds to html with settings layout" do
    get family_exports_path
    assert_response :success
    assert_select "title" # rendered with layout
  end

  test "index responds to turbo_stream without raising MissingTemplate" do
    get family_exports_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_redirected_to family_exports_path
  end

  test "non-admin cannot delete export" do
    export = @family.family_exports.create!(status: "completed")
    sign_in @non_admin

    assert_no_difference "@family.family_exports.count" do
      delete family_export_path(export)
    end

    assert_response :not_found
  end
end
