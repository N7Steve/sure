require "test_helper"
require "csv"

class Family::TransactionCsvExporterTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @user.update!(locale: "es")
    @family = @user.family
    @account = @user.accessible_accounts.first
    @other_account = @user.accessible_accounts.where.not(id: @account.id).first || @family.accounts.create!(
      owner: @user,
      name: "Other CSV account",
      balance: 0,
      currency: @family.currency,
      accountable: Depository.new
    )
    @allowed_category = @family.categories.create!(name: "CSV Allowed", color: "#111111")
    @excluded_parent = @family.categories.create!(name: "CSV Excluded Parent", color: "#222222")
    @excluded_child = @family.categories.create!(name: "CSV Excluded Child", color: "#333333", parent: @excluded_parent)
    @excluded_tag = @family.tags.create!(name: "CSV Excluded Tag", color: "#444444")
    @allowed_tag = @family.tags.create!(name: "CSV Allowed Tag", color: "#555555")
  end

  test "exports only selected dates and accounts and applies category and tag exclusions" do
    create_transaction(
      account: @account,
      name: "Included transaction",
      date: Date.new(2026, 2, 15),
      amount: 42.5,
      category: @allowed_category,
      tags: [ @allowed_tag ]
    )
    create_transaction(account: @account, name: "Before range", date: Date.new(2026, 1, 31))
    create_transaction(account: @account, name: "After range", date: Date.new(2026, 3, 1))
    create_transaction(account: @other_account, name: "Other account", date: Date.new(2026, 2, 15))
    create_transaction(account: @account, name: "Excluded parent", date: Date.new(2026, 2, 15), category: @excluded_parent)
    create_transaction(account: @account, name: "Excluded child", date: Date.new(2026, 2, 15), category: @excluded_child)
    create_transaction(
      account: @account,
      name: "Excluded by one of several tags",
      date: Date.new(2026, 2, 15),
      tags: [ @excluded_tag, @allowed_tag ]
    )

    result = exporter.generate
    rows = parse_csv(result)

    assert_equal 1, result.record_count
    assert_equal Family::TransactionCsvExporter::HEADERS, rows.headers
    assert_equal [ "Included transaction" ], rows.map { |row| row["title"] }
    assert_equal @account.name, rows.first["source_account"]
    assert_nil rows.first["destination_account"]
    assert_equal "42,5", rows.first["amount"]
    assert_equal "2026-02-15", rows.first["date"]
    assert_equal @allowed_category.name, rows.first["category"]
    assert_equal @allowed_tag.name, rows.first["tags"]
  end

  test "includes both date boundaries" do
    create_transaction(account: @account, name: "First day", date: Date.new(2026, 2, 1))
    create_transaction(account: @account, name: "Last day", date: Date.new(2026, 2, 28))

    rows = parse_csv(exporter.generate)

    assert_equal [ "First day", "Last day" ], rows.map { |row| row["title"] }
  end

  test "protects spreadsheet text fields from formulas" do
    create_transaction(account: @account, name: "=SUM(1,1)", date: Date.new(2026, 2, 15))

    row = parse_csv(exporter.generate).first

    assert_equal "'=SUM(1,1)", row["title"]
  end

  test "uses an Excel-friendly UTF-8 semicolon CSV for Spanish users" do
    create_transaction(account: @account, name: "Café", date: Date.new(2026, 2, 15))

    result = exporter.generate
    csv = result.io.string

    assert csv.start_with?(Family::TransactionCsvExporter::UTF_8_BOM)
    header = csv.delete_prefix(Family::TransactionCsvExporter::UTF_8_BOM).lines.first.chomp
    assert_equal Family::TransactionCsvExporter::HEADERS.join(";"), header
    assert_equal "Café", parse_csv(result).first["title"]
  end

  test "uses comma-separated columns and decimal point for English users" do
    @user.update!(locale: "en")
    create_transaction(account: @account, name: "English CSV", amount: 42.5, date: Date.new(2026, 2, 15))

    data = exporter.generate.io.string.delete_prefix(Family::TransactionCsvExporter::UTF_8_BOM)
    rows = CSV.parse(data, headers: true, col_sep: ",")

    assert_equal Family::TransactionCsvExporter::HEADERS, rows.headers
    assert_equal "42.5", rows.first["amount"]
  end

  test "includes source and destination accounts for transfers" do
    create_transfer(
      from_account: @account,
      to_account: @other_account,
      amount: 75,
      date: Date.new(2026, 2, 15),
      currency: @account.currency
    )

    row = parse_csv(exporter.generate).find { |candidate| candidate["title"] == "Transfer to #{@other_account.name}" }

    assert row
    assert_equal @account.name, row["source_account"]
    assert_equal @other_account.name, row["destination_account"]
  end

  test "drive schema includes stable identifiers currency and update time" do
    entry = create_transaction(
      account: @account,
      name: "Drive transaction",
      amount: 42.5,
      date: Date.new(2026, 2, 15)
    )

    result = Family::TransactionCsvExporter.new(export_record, schema: :drive).generate
    data = result.io.string.delete_prefix(Family::TransactionCsvExporter::UTF_8_BOM)
    row = CSV.parse(data, headers: true, col_sep: ";").first

    assert_equal Family::TransactionCsvExporter::DRIVE_HEADERS, row.headers
    assert_equal entry.entryable.id, row["transaction_id"]
    assert_equal entry.id, row["entry_id"]
    assert_equal @account.id, row["source_account_id"]
    assert_equal entry.currency, row["currency"]
    assert_equal entry.updated_at.iso8601, row["updated_at"]
  end

  test "clean drive schema omits internal identifiers and update time" do
    subcategory = @family.categories.create!(name: "CSV Child", color: "#666666", parent: @allowed_category)
    entry = create_transaction(
      account: @account,
      name: "Readable, transaction",
      amount: 42.5,
      date: Date.new(2026, 2, 15),
      category: subcategory,
      tags: [ @allowed_tag ]
    )

    result = Family::TransactionCsvExporter.new(clean_drive_schedule, schema: :drive).generate
    rows = parse_clean_csv(result)
    row = rows.find { |candidate| candidate["title"] == "Readable, transaction" }

    assert_equal Encoding::UTF_8, result.io.string.encoding
    assert_not result.io.string.start_with?(Family::TransactionCsvExporter::UTF_8_BOM)
    assert_equal Family::TransactionCsvExporter::DRIVE_CLEAN_HEADERS.join(","), result.io.string.lines.first.chomp
    assert_equal Family::TransactionCsvExporter::DRIVE_CLEAN_HEADERS, rows.headers
    assert_not_includes rows.headers, "entry_id"
    assert_not_includes rows.headers, "source_account_id"
    assert_not_includes rows.headers, "destination_account_id"
    assert_not_includes rows.headers, "updated_at"
    assert row
    assert_equal entry.entryable.id, row["transaction_id"]
    assert_equal "expense", row["type"]
    assert_equal "42.5", row["amount"]
    assert_equal @allowed_category.name, row["category"]
    assert_equal subcategory.name, row["subcategory"]
    assert_equal @allowed_tag.name, row["tags"]
  end

  test "clean drive schema can omit category and tags independently" do
    create_transaction(account: @account, name: "Optional columns", date: Date.new(2026, 2, 15))
    schedule = clean_drive_schedule(include_category: false, include_tags: true)

    rows = parse_clean_csv(Family::TransactionCsvExporter.new(schedule, schema: :drive).generate)

    assert_not_includes rows.headers, "category"
    assert_not_includes rows.headers, "subcategory"
    assert_includes rows.headers, "tags"
  end

  test "clean drive schema makes income direction and amount explicit" do
    entry = create_transaction(
      account: @account,
      name: "Salary",
      amount: -3207.88,
      date: Date.new(2026, 2, 15)
    )

    rows = parse_clean_csv(Family::TransactionCsvExporter.new(clean_drive_schedule, schema: :drive).generate)
    row = rows.find { |candidate| candidate["transaction_id"] == entry.entryable.id }

    assert row
    assert_equal "income", row["type"]
    assert_equal "3207.88", row["amount"]
    assert_nil row["source_account"]
    assert_equal @account.name, row["destination_account"]
  end

  test "clean drive schema exports a transfer as one logical row" do
    transfer = create_transfer(
      from_account: @account,
      to_account: @other_account,
      amount: 75.25,
      date: Date.new(2026, 2, 15),
      currency: @account.currency
    )

    schedule = clean_drive_schedule(account_ids: [ @account.id, @other_account.id ])
    rows = parse_clean_csv(Family::TransactionCsvExporter.new(schedule, schema: :drive).generate)
    transfer_rows = rows.select { |row| row["transaction_id"] == transfer.id }

    assert_equal 1, transfer_rows.size
    assert_equal "transfer", transfer_rows.first["type"]
    assert_equal "75.25", transfer_rows.first["amount"]
    assert_equal @account.name, transfer_rows.first["source_account"]
    assert_equal @other_account.name, transfer_rows.first["destination_account"]
  end

  private
    def exporter
      Family::TransactionCsvExporter.new(export_record)
    end

    def export_record
      @family.family_exports.new(
        export_type: :transactions_csv,
        requested_by: @user,
        start_date: Date.new(2026, 2, 1),
        end_date: Date.new(2026, 2, 28),
        filters: {
          account_ids: [ @account.id ],
          excluded_category_ids: [ @excluded_parent.id ],
          excluded_tag_ids: [ @excluded_tag.id ]
        }
      )
    end

    def clean_drive_schedule(include_category: true, include_tags: true, account_ids: [ @account.id ])
      GoogleDriveExportSchedule.new(
        family: @family,
        user: @user,
        timezone: "UTC",
        date_range: :all_history,
        filters: {
          account_ids: account_ids,
          export_format: "clean",
          include_category: include_category,
          include_tags: include_tags
        }
      )
    end

    def parse_csv(result)
      data = result.io.string.delete_prefix(Family::TransactionCsvExporter::UTF_8_BOM)
      CSV.parse(data, headers: true, col_sep: ";")
    end

    def parse_clean_csv(result)
      CSV.parse(result.io.string, headers: true, col_sep: ",")
    end
end
