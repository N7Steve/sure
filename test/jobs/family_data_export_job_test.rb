require "test_helper"

class FamilyDataExportJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @export = @family.family_exports.create!
  end

  test "marks export as processing then completed" do
    assert_equal "pending", @export.status

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "completed", @export.status
    assert @export.export_file.attached?
  end

  test "generates and attaches a filtered transaction CSV" do
    user = users(:family_admin)
    account = user.accessible_accounts.first
    account.entries.create!(
      date: Date.current,
      amount: 12.34,
      currency: account.currency,
      name: "CSV job transaction",
      entryable: Transaction.new(kind: "standard")
    )
    export = @family.family_exports.create!(
      export_type: :transactions_csv,
      requested_by: user,
      start_date: Date.current,
      end_date: Date.current,
      filters: { account_ids: [ account.id ] }
    )

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(export)
    end

    export.reload
    assert export.completed?
    assert export.export_file.attached?
    assert_equal "text/csv; charset=utf-8", export.export_file.content_type
    assert_operator export.record_count, :>=, 1
    assert_includes export.export_file.download, "CSV job transaction"
  end

  test "does not restart an export in a terminal status" do
    @export.update_columns(status: "failed")

    Family::DataExporter.any_instance.expects(:generate_export).never

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    assert_equal "failed", @export.reload.status
  end

  test "marks export as failed on error" do
    # Mock the exporter to raise an error
    Family::DataExporter.any_instance.stubs(:generate_export).raises(StandardError, "Export failed")

    perform_enqueued_jobs do
      FamilyDataExportJob.perform_later(@export)
    end

    @export.reload
    assert_equal "failed", @export.status
  end
end
