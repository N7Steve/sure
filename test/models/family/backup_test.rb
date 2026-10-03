require "test_helper"

class Family::BackupTest < ActiveSupport::TestCase
  setup do
    @source = Family.create!(name: "Portable family", currency: "EUR", country: "ES", timezone: "Europe/Madrid", date_format: "%d/%m/%Y")
    @target = families(:empty)
    @account = @source.accounts.create!(name: "Checking", accountable: Depository.new, balance: 900, currency: "EUR")
    @destination = @source.accounts.create!(name: "Savings", accountable: Depository.new, balance: 100, currency: "EUR")
    @merchant = @source.merchants.create!(name: "Utilities", color: "#4da568", website_url: "https://example.com")
    @category = @source.categories.create!(name: "Utilities", color: "#4da568")
    @tag = @source.tags.create!(name: "Household", color: "#4da568")
  end

  test "round trips Agenda definitions, tags, rejected occurrences and both transfer entries" do
    payment = @source.scheduled_payments.create!(
      account: @account, target_account: @destination, title: "Savings transfer", amount: 100,
      currency: "EUR", payment_type: "transfer", frequency: "monthly", frequency_day: 15,
      start_date: Date.new(2026, 1, 15), next_run_date: Date.new(2026, 10, 15),
      category: @category, merchant: @merchant, auto_confirm: false, occurrences_count: 9
    )
    payment.tags << @tag
    outflow = transaction(@account, "Savings", 100)
    inflow = transaction(@destination, "Savings", -100)
    payment.scheduled_payment_entries.create!(scheduled_date: outflow.date, status: "confirmed", entry: outflow, transfer_entry: inflow)
    payment.scheduled_payment_entries.create!(scheduled_date: Date.new(2026, 9, 15), status: "rejected", rejection_reason: "Already paid")

    restore!

    restored = @target.scheduled_payments.find_by!(title: payment.title)
    assert_equal "Savings", restored.target_account.name
    assert_equal "Utilities", restored.category.name
    assert_equal "Utilities", restored.merchant.name
    assert_equal [ "Household" ], restored.tags.pluck(:name)
    assert_equal payment.next_run_date, restored.next_run_date
    assert_equal 9, restored.occurrences_count
    confirmed = restored.scheduled_payment_entries.find_by!(status: "confirmed")
    assert_equal BigDecimal("100"), confirmed.entry.amount
    assert_equal BigDecimal("-100"), confirmed.transfer_entry.amount
    assert_equal "Already paid", restored.scheduled_payment_entries.find_by!(status: "rejected").rejection_reason
  end

  test "round trips custom account and provider merchant icons, receipts and documents as bytes" do
    entry = transaction(@account, "Receipt", 20)
    provider = ProviderMerchant.create!(name: "Portable provider", source: "plaid")
    entry.transaction.update!(merchant: provider)
    customization = @source.merchant_customizations.create!(merchant: provider)
    attach(@account.custom_logo, "account.png", file_fixture("square-placeholder.png").binread, "image/png")
    attach(customization.custom_logo, "merchant.png", file_fixture("square-placeholder.png").binread, "image/png")
    attach(entry.transaction.attachments, "receipt.pdf", "original receipt bytes", "application/pdf")
    document = @source.family_documents.create!(filename: "contract.pdf", status: "ready", metadata: { "note" => "Keep this" })
    attach(document.file, "contract.pdf", "original contract bytes", "application/pdf")

    result = restore!

    assert_equal @account.custom_logo.download, @target.accounts.find_by!(name: "Checking").custom_logo.download
    assert_equal customization.custom_logo.download, @target.merchant_customizations.sole.custom_logo.download
    assert_equal "original receipt bytes", @target.transactions.sole.attachments.sole.download
    assert_equal "original contract bytes", @target.family_documents.sole.file.download
    assert_equal document.metadata, @target.family_documents.sole.metadata
    assert_equal 4, result[:verification]["verified_attachments"]
  end

  test "document upload stores original bytes for subsequent backups" do
    adapter = mock("vector store")
    VectorStore.stubs(:adapter).returns(adapter)
    adapter.expects(:create_store).returns(OpenStruct.new(success?: true, data: { id: "store-portable" }))
    adapter.expects(:upload_file).with(store_id: "store-portable", file_content: "original document", filename: "notes.txt")
      .returns(OpenStruct.new(success?: true, data: { file_id: "file-portable" }))
    document = @source.upload_document(file_content: "original document", filename: "notes.txt")
    assert_equal "original document", document.file.download

    restore!

    assert_equal "original document", @target.family_documents.sole.file.download
  end

  test "reports legacy documents whose source never retained the original" do
    document = @source.family_documents.create!(filename: "legacy.pdf", file_size: 100, provider_file_id: "remote-only", status: "ready")
    content = nil
    report = nil
    Zip::File.open_buffer(Family::DataExporter.new(@source).generate_export) do |zip|
      content = zip.read("all.ndjson")
      report = JSON.parse(zip.read("backup_report.json"))
    end
    assert_equal document.id, report["unavailable_document_originals"].sole["id"]
    preflight = SureImport::Preflight.new(family: @target, content: content).call
    assert preflight.valid?, preflight.error_message
    assert_equal "source_original_unavailable", preflight.warnings.sole[:code]
    result = Family::DataImporter.new(@target, content).import!
    assert_equal "legacy.pdf", result[:verification]["warnings"].sole[:details][:filename]
  end

  test "round trips goals and pledge links inside transaction metadata" do
    entry = transaction(@destination, "Saved", -100)
    goal = @source.goals.build(name: "Emergency fund", currency: "EUR", target_amount: 5000, notes: "Six months", progress_basis: "contributions")
    goal.goal_accounts.build(account: @destination, allocated_amount: 100)
    goal.save!
    pledge = goal.goal_pledges.create!(account: @destination, amount: 100, currency: "EUR", kind: "transfer", status: "matched", matched_transaction: entry.transaction)
    entry.transaction.update_columns(extra: { "goal" => { "pledge_id" => pledge.id }, "memo" => "Preserve" }, locked_attributes: { "merchant_id" => true })

    restore!

    restored = @target.goals.sole
    assert_equal goal.notes, restored.notes
    assert_equal "contributions", restored.progress_basis
    assert_equal BigDecimal("100"), restored.goal_accounts.sole.allocated_amount
    restored_pledge = restored.goal_pledges.sole
    assert_equal "matched", restored_pledge.status
    assert_equal restored_pledge.id, restored_pledge.matched_transaction.extra.dig("goal", "pledge_id")
    assert_equal "Preserve", restored_pledge.matched_transaction.extra["memo"]
  end

  test "round trips all accountable details, property addresses and family preferences" do
    property = @source.accounts.create!(name: "Home", accountable: Property.new(year_built: 2001, area_value: 120, area_unit: "sqm"), balance: 300000, currency: "EUR")
    property.accountable.create_address!(line1: "Main street", locality: "Madrid", country: "ES")
    @source.update!(month_start_day: 15, default_account_sharing: "private", enabled_currencies: %w[EUR USD], personal_budgets: true)
    @account.update!(enable_category_matcher: false, locked_attributes: { "balance" => true })
    restore!

    @target.reload
    assert_equal 15, @target.month_start_day
    assert_equal "Europe/Madrid", @target.timezone
    assert_equal "private", @target.default_account_sharing
    assert_equal %w[EUR USD], @target.enabled_currencies
    assert @target.personal_budgets
    restored = @target.accounts.find_by!(name: "Home").accountable
    assert_equal 2001, restored.year_built
    assert_equal BigDecimal("120"), restored.area_value
    assert_equal "Madrid", restored.address.locality
    assert_not @target.accounts.find_by!(name: "Checking").enable_category_matcher
  end

  test "round trips provider credentials, raw payloads and account links" do
    item = @source.simplefin_items.create!(name: "Bank", access_url: "https://test-token@example.com/simplefin")
    provider_account = item.simplefin_accounts.create!(account_id: "checking", name: "Checking", account_type: "checking", currency: "EUR", current_balance: 900, raw_payload: { "pending" => true })
    @account.account_providers.create!(provider: provider_account)

    restore!

    restored = @target.simplefin_items.sole
    assert_equal item.access_url, restored.access_url
    assert_equal provider_account.raw_payload, restored.simplefin_accounts.sole.raw_payload
    assert_equal restored.simplefin_accounts.sole, @target.accounts.find_by!(name: "Checking").account_providers.sole.provider
  end

  test "round trips statement files and reconciliation links" do
    entry = transaction(@account, "Reconciled", 10)
    statement = AccountStatement.create_from_upload!(family: @source, account: @account,
      file: Rack::Test::UploadedFile.new(file_fixture("imports/sample_bank_statement.pdf"), "application/pdf"))
    entry.update!(reconciled_at: Time.current, reconciled_by_statement_id: statement.id)

    restore!

    restored = @target.account_statements.sole
    assert_equal statement.original_file.download, restored.original_file.download
    assert_equal restored.id, @target.entries.find_by!(name: "Reconciled").reconciled_by_statement_id
    assert_equal "Checking", restored.account.name
  end

  test "corruption and missing references roll back without partial restoration" do
    records = JSON.parse(Family::Backup.new(@source).generate_ndjson.lines.first)
    content = Family::Backup.new(@source).generate_ndjson.sub('"name":"Checking"', '"name":"Changed"')
    assert_no_difference [ "Account.count", "ActiveStorage::Blob.count" ] do
      error = assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
      assert_match(/checksum/, error.message)
    end
    assert_equal "BackupManifest", records["type"]
  end

  test "preflight rejects dangling references even with a recomputed manifest" do
    transaction(@account, "Broken reference", 1)
    content = rewrite_backup do |records|
      entry = records.find { |row| row.dig("data", "model") == "Entry" }
      entry["data"]["attributes"]["account_id"] = SecureRandom.uuid
    end
    result = SureImport::Preflight.new(family: @target, content: content).call
    assert_not result.valid?
    assert_match(/Missing Account reference/, result.error_message)
    assert_no_difference "Account.count" do
      assert_raises(Family::Backup::InvalidBackupError) { Family::DataImporter.new(@target, content).import! }
    end
  end

  test "preflight rejects changed file bytes even with a recomputed manifest" do
    attach(@account.custom_logo, "logo.png", file_fixture("square-placeholder.png").binread, "image/png")
    content = rewrite_backup do |records|
      records.find { |row| row["type"] == "BackupAttachment" }["data"]["content"] = Base64.strict_encode64("tampered")
    end
    result = SureImport::Preflight.new(family: @target, content: content).call
    assert_not result.valid?
    assert_match(/Attachment checksum mismatch/, result.error_message)
  end

  test "the existing family fixture produces a complete valid graph" do
    # This old fixture names a nonexistent "checking" account. A full snapshot
    # intentionally refuses dangling references rather than dropping the link.
    imports(:pdf_with_rows).update_column(:account_id, accounts(:depository).id)
    content = nil
    Zip::File.open_buffer(Family::DataExporter.new(families(:dylan_family)).generate_export) { |zip| content = zip.read("all.ndjson") }
    preflight = SureImport::Preflight.new(family: @target, content: content).call
    assert preflight.valid?, preflight.error_message
  end

  test "every family-owned table is covered or has a documented exclusion" do
    tables = ApplicationRecord.connection.select_values("SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'family_id'")
    covered = Family::Backup.models.values.map(&:table_name) + Family::Backup::EXCLUDED_FAMILY_TABLES.keys
    assert_empty tables - covered
  end

  test "restores the existing family fixture graph with readback verification" do
    imports(:pdf_with_rows).update_column(:account_id, accounts(:depository).id)
    # These fixture-only kinds predate the current transaction enum.
    transactions(:transfer_out).update_column(:kind, "funds_movement")
    transactions(:transfer_in).update_column(:kind, "funds_movement")
    source = families(:dylan_family)
    content = Family::Backup.new(source).generate_ndjson
    # Simulate a separate instance, where these member emails are available.
    source.users.each { |user| user.update_column(:email, "source-#{user.id}@example.com") }
    source.plaid_items.each { |item| item.update_column(:plaid_id, "source-#{item.id}") }

    result = Family::DataImporter.new(@target, content).import!

    assert_equal "matched", result[:verification]["status"]
    assert_equal source.accounts.count, @target.accounts.count
    assert_equal source.entries.count, @target.entries.count
    assert_equal source.scheduled_payments.count, @target.scheduled_payments.count
    assert_equal source.imports.count, @target.imports.count
  end

  test "preserves uploaded import source files and historical import links" do
    import = @source.imports.create!(type: "PdfImport", account: @account, status: "complete")
    attach(import.pdf_file, "source.pdf", file_fixture("imports/sample_bank_statement.pdf").binread, "application/pdf")
    entry = transaction(@account, "From PDF", 40)
    entry.update_columns(import_id: import.id)

    restore!

    restored = @target.imports.where(type: "PdfImport").sole
    assert_equal import.pdf_file.download, restored.pdf_file.download
    assert_equal restored.id, @target.entries.find_by!(name: "From PDF").import_id
  end

  test "session restoration maps shared provider merchants and does not schedule sync" do
    provider = ProviderMerchant.create!(name: "Shared portable merchant", source: "plaid")
    transaction(@account, "Provider purchase", 15).transaction.update!(merchant: provider)
    session = @target.import_sessions.create!(import_type: "SureImport", expected_chunks: 1)
    session.attach_chunk!(sequence: 1, content: Family::Backup.new(@source).generate_ndjson, filename: "all.ndjson", content_type: "application/x-ndjson")
    @target.expects(:sync_later).never
    session.publish

    assert session.reload.complete?, session.error_details.inspect
    assert_equal provider, @target.transactions.sole.merchant
    assert session.source_mappings.exists?(source_type: "Merchant", source_id: provider.id, target_id: provider.id)
  end

  test "rule operands and notification deduplication survive restoration" do
    other_tag = @source.tags.create!(name: "Second tag", color: "#4da568")
    entry = transaction(@account, "Rule target", 1)
    rule = @source.rules.build(name: "Portable rule", resource_type: "transaction", active: true)
    rule.conditions.build(condition_type: "transaction_account", operator: "equal", value: @account.id)
    rule.actions.build(action_type: "set_transaction_tags", value: [ @tag.id, other_tag.id ].join(","))
    rule.actions.build(action_type: "set_transaction_category", value: @category.id)
    rule.save!
    NotificationDelivery.create!(rule: rule, transaction_record: entry.transaction)

    restore!

    restored = @target.rules.sole
    assert_equal @target.accounts.find_by!(name: "Checking").id, restored.conditions.sole.value
    assert_equal @target.tags.order(:name).pluck(:id).sort, restored.actions.find_by!(action_type: "set_transaction_tags").value.split(",").sort
    assert_equal @target.categories.find_by!(name: "Utilities").id, restored.actions.find_by!(action_type: "set_transaction_category").value
    assert_equal @target.transactions.sole.id, NotificationDelivery.find_by!(rule: restored).transaction_id
  end

  test "round trips member preferences, ownership and sharing without replacing login credentials" do
    admin = @source.users.create!(email: "portable-admin@example.com", password: "password123", role: "admin", locale: "es", theme: "dark")
    member = @source.users.create!(email: "portable-member@example.com", password: "password123", role: "member", preferences: { "preview_features_enabled" => true })
    @account.update!(owner: admin)
    @account.account_shares.create!(user: member, permission: "read_only", include_in_finances: false)
    source_budget = @source.budgets.create!(user: member, currency: "EUR", start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31), budgeted_spending: 100)
    BudgetShare.create!(owner: admin, viewer: member, permission: "read_only")
    content = Family::Backup.new(@source).generate_ndjson
    assert_not content.include?(admin.password_digest)
    member.destroy!
    importing_user = users(:empty)
    digest = importing_user.password_digest

    Family::DataImporter.new(@target, content).import!

    importing_user.reload
    assert_equal digest, importing_user.password_digest
    assert_equal "dark", importing_user.theme
    assert_equal "es", importing_user.locale
    restored_member = @target.users.find_by!(email: "portable-member@example.com")
    assert_equal member.preferences, restored_member.preferences
    assert_equal importing_user, @target.accounts.find_by!(name: "Checking").owner
    share = @target.accounts.find_by!(name: "Checking").account_shares.sole
    assert_equal restored_member, share.user
    assert_not share.include_in_finances
    assert_equal "read_only", share.permission
    assert_equal restored_member, @target.budgets.find_by!(start_date: source_budget.start_date).user
    assert BudgetShare.exists?(owner: importing_user, viewer: restored_member, permission: "read_only")
  end

  test "late restoration errors roll back rows, family preferences and files" do
    attach(@account.custom_logo, "logo.png", file_fixture("square-placeholder.png").binread, "image/png")
    before = @target.attributes
    Family::Backup::Restorer.any_instance.stubs(:verify_records!).raises(Family::Backup::InvalidBackupError, "Readback failed")
    assert_no_difference [ "Account.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ] do
      assert_raises(Family::Backup::InvalidBackupError) { restore! }
    end
    assert_equal before, @target.reload.attributes
  end

  test "refuses merging a full backup into existing financial data" do
    @target.accounts.create!(name: "Already here", accountable: Depository.new, currency: "EUR", balance: 1)
    assert_no_difference "Account.count" do
      assert_raises(Family::Backup::InvalidBackupError) { restore! }
    end
  end

  test "SureImport verifies the snapshot and retries without duplicates or sync" do
    content = Family::Backup.new(@source).generate_ndjson
    import = @target.imports.create!(type: "SureImport")
    attach(import.ndjson_file, "all.ndjson", content, "application/x-ndjson")
    assert import.sure_preflight.valid?
    @target.expects(:sync_later).never
    import.publish
    assert import.reload.complete?, import.error
    assert_equal "matched", import.verification_status
    assert import.data_committed?
    assert_not import.revertable?
    assert_no_difference([ "Account.count", "Entry.count" ]) { import.import! }
  end

  test "retry verification detects a missing restored original" do
    attach(@account.custom_logo, "logo.png", file_fixture("square-placeholder.png").binread, "image/png")
    import = @target.imports.create!(type: "SureImport")
    attach(import.ndjson_file, "all.ndjson", Family::Backup.new(@source).generate_ndjson, "application/x-ndjson")
    import.publish
    assert import.reload.complete?, import.error
    @target.accounts.find_by!(name: "Checking").custom_logo.attachment.destroy!

    assert_no_difference "Account.count" do
      assert_raises(Family::Backup::InvalidBackupError) { import.import! }
    end
    assert_equal "failed", import.reload.verification_status
  end

  private
    def transaction(account, name, amount)
      account.entries.create!(name: name, amount: amount, currency: "EUR", date: Date.new(2026, 10, 1), entryable: Transaction.new(category: @category, merchant: @merchant))
    end

    def attach(attachment, filename, bytes, content_type)
      attachment.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
    end

    def restore!
      content = nil
      Zip::File.open_buffer(Family::DataExporter.new(@source).generate_export) { |zip| content = zip.read("all.ndjson") }
      Family::DataImporter.new(@target, content).import!
    end

    def rewrite_backup
      records = Family::Backup.new(@source).generate_ndjson.each_line.map { |line| JSON.parse(line) }
      yield records
      payload = records.drop(1).map(&:to_json).join("\n")
      records.first["data"]["sha256"] = Digest::SHA256.hexdigest(payload)
      records.map(&:to_json).join("\n")
    end
end
