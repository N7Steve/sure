require "test_helper"
require "csv"

class Family::AccountSnapshotCsvExporterTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @cash_account = accounts(:depository)
    @loan_account = accounts(:loan)

    @cash_account.update!(
      name: "Bankinter Nomina",
      institution_name: "Bankinter",
      balance: -4251.91,
      currency: "EUR",
      notes: "Pending reconciliation",
      financial_treatment: "tracking"
    )
    @cash_account.accountable.update!(subtype: "checking")
    @loan_account.update!(name: "Hipoteca Home", institution_name: "CA Auto Bank", currency: "EUR")
    @loan_account.accountable.update!(subtype: "mortgage")
  end

  test "exports selected account positions as a standard analytical snapshot" do
    travel_to Time.zone.parse("2026-09-21 10:00:00") do
      result = Family::AccountSnapshotCsvExporter.new(schedule).generate
      rows = CSV.parse(result.io.string, headers: true, col_sep: ",")
      cash = rows.find { |row| row["position_id"] == @cash_account.id }
      loan = rows.find { |row| row["position_id"] == @loan_account.id }

      assert_equal Encoding::UTF_8, result.io.string.encoding
      assert_not result.io.string.start_with?(Family::TransactionCsvExporter::UTF_8_BOM)
      assert_equal Family::AccountSnapshotCsvExporter::HEADERS, rows.headers
      assert_equal 2, result.record_count

      assert_equal "2026-09-21", cash["snapshot_date"]
      assert_equal "Bankinter", cash["institution"]
      assert_equal "Bankinter Nomina", cash["name"]
      assert_equal "cash", cash["type"]
      assert_equal "checking_account", cash["subtype"]
      assert_equal "tracking", cash["scope"]
      assert_equal "4251.91", cash["value"]
      assert_equal "EUR", cash["currency"]
      assert_equal "Pending reconciliation", cash["notes"]

      assert_equal "liability", loan["type"]
      assert_equal "mortgage", loan["subtype"]
      assert_equal "included", loan["scope"]
    end
  end

  private
    def schedule
      GoogleDriveExportSchedule.new(
        family: @family,
        user: @user,
        timezone: "Europe/Madrid",
        filters: {
          account_ids: [ @cash_account.id, @loan_account.id ],
          export_format: "snapshot"
        }
      )
    end
end
