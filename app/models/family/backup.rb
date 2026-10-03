require "base64"
require "digest"

# The portable family snapshot. CSVs and the older NDJSON records remain useful
# for interchange, but cannot represent the complete relational state.
class Family::Backup
  class InvalidBackupError < StandardError
    def code = "invalid_backup"
  end
  VERSION = 1
  TYPES = %w[BackupManifest BackupRecord BackupAttachment].freeze

  PROVIDERS = %w[Akahu Binance Brex Coinbase Coinspot Coinstats EnableBanking Fio Ibkr IndexaCapital Kraken Lunchflow Mercury Monobank OnchainWallet Plaid Questrade Redbark Simplefin Snaptrade Sophtron TradeRepublic Trading212 Up Wise].freeze
  MODEL_NAMES = (%w[
    Family User Account AccountShare BudgetShare Depository Investment Crypto
    Property Vehicle OtherAsset CreditCard Loan OtherLiability Address Category
    Tag Merchant MerchantCustomization FamilyMerchantAssociation Entry Transaction
    Trade Valuation Balance Holding AccountProvider Security Security::Price
    Budget BudgetCategory Rule Rule::Condition Rule::Action RuleRun NotificationDelivery
    RecurringTransaction RecurrenceRule RecurringOccurrence RecurringAllocation
    RecurringPriceChange RecurringMatchRejection Transfer RejectedTransfer Tagging
    ScheduledPayment ScheduledPaymentEntry Goal GoalAccount GoalPledge
    FamilyDocument AccountStatement Chat Message ToolCall Insight DataEnrichment
    CategorizationComparison GoogleDriveConnection GoogleDriveOauthConfiguration
    GoogleDriveExportSchedule GoogleDriveExportTarget GoogleDriveExportRun
    FinancekitItem FinancekitAccountLineage FinancekitAccount FinancekitBatch
    FinancekitTransaction FinancekitBalanceObservation FinancekitConflict
    Import ImportSession ImportSourceMapping Import::Row Import::Mapping
    ExchangeRate ExchangeRatePair
  ] + PROVIDERS.flat_map { |prefix| [ "#{prefix}Item", "#{prefix}Account" ] }).freeze

  EXCLUDED_FAMILY_TABLES = {
    "family_exports" => "Previously generated backups are output artifacts, not live family data",
    "subscriptions" => "Billing contracts belong to the destination instance",
    "invitations" => "Pending authentication links must be issued by the destination instance",
    "debug_log_entries" => "Operational diagnostics are instance history",
    "llm_usages" => "Provider usage and billing are instance history"
  }.freeze

  # Instance authentication and service-side indexes are deliberately regenerated.
  EXCLUDED_ATTRIBUTES = {
    "Family" => %w[stripe_customer_id vector_store_id bills_feed_token],
    "User" => %w[password_digest otp_secret otp_required otp_backup_codes otp_last_used_at webauthn_id unconfirmed_email sessions_count last_login_at],
    "Account" => %w[classification],
    "FamilyDocument" => %w[provider_file_id],
    "FinancekitBatch" => %w[sync_id]
  }.freeze
  PARENTS = {
    "Entry" => [ "Account", "account_id" ],
    "Balance" => [ "Account", "account_id" ],
    "Holding" => [ "Account", "account_id" ],
    "AccountProvider" => [ "Account", "account_id" ],
    "AccountShare" => [ "Account", "account_id" ],
    "BudgetShare" => [ "User", "owner_id" ],
    "BudgetCategory" => [ "Budget", "budget_id" ],
    "Rule::Condition" => [ "Rule", "rule_id" ],
    "Rule::Action" => [ "Rule", "rule_id" ],
    "RuleRun" => [ "Rule", "rule_id" ],
    "NotificationDelivery" => [ "Rule", "rule_id" ],
    "RecurrenceRule" => [ "RecurringTransaction", "recurring_transaction_id" ],
    "RecurringAllocation" => [ "RecurringOccurrence", "recurring_occurrence_id" ],
    "RecurringPriceChange" => [ "RecurringTransaction", "recurring_transaction_id" ],
    "RecurringMatchRejection" => [ "RecurringTransaction", "recurring_transaction_id" ],
    "ScheduledPaymentEntry" => [ "ScheduledPayment", "scheduled_payment_id" ],
    "GoalAccount" => [ "Goal", "goal_id" ],
    "GoalPledge" => [ "Goal", "goal_id" ],
    "Chat" => [ "User", "user_id" ],
    "Message" => [ "Chat", "chat_id" ],
    "ToolCall" => [ "Message", "message_id" ],
    "Security::Price" => [ "Security", "security_id" ],
    "GoogleDriveExportTarget" => [ "GoogleDriveExportSchedule", "google_drive_export_schedule_id" ],
    "GoogleDriveExportRun" => [ "GoogleDriveExportSchedule", "google_drive_export_schedule_id" ],
    "FinancekitAccount" => [ "FinancekitItem", "financekit_item_id" ],
    "FinancekitBatch" => [ "FinancekitItem", "financekit_item_id" ],
    "FinancekitTransaction" => [ "FinancekitAccountLineage", "financekit_account_lineage_id" ],
    "FinancekitBalanceObservation" => [ "FinancekitAccountLineage", "financekit_account_lineage_id" ],
    "Import::Row" => [ "Import", "import_id" ],
    "Import::Mapping" => [ "Import", "import_id" ]
  }.merge(PROVIDERS.to_h { |prefix| [ "#{prefix}Account", [ "#{prefix}Item", "#{prefix.underscore}_item_id" ] ] }).freeze
  POLYMORPHIC_PARENTS = {
    "Address" => %w[Property],
    "Tagging" => %w[Transaction ScheduledPayment],
    "DataEnrichment" => %w[Account Entry Transaction Trade Valuation Depository Investment Crypto Property Vehicle OtherAsset CreditCard Loan OtherLiability]
  }.freeze

  def self.snapshot?(content)
    content.each_line.any? do |line|
      record = JSON.parse(line)
      record.is_a?(Hash) && TYPES.include?(record["type"])
    rescue JSON::ParserError, TypeError
      false
    end
  end

  def self.models
    @models ||= MODEL_NAMES.index_with(&:constantize).freeze
  end

  def self.attachment_model(name, attributes)
    model = models.fetch(name)
    model == Import && Import::TYPES.include?(attributes["type"]) ? attributes["type"].constantize : model
  end

  def self.has_attachments?(model)
    model == Import ? Import::TYPES.any? { |type| type.constantize.attachment_reflections.any? } : model.attachment_reflections.any?
  end

  def initialize(family)
    @family = family
    @scopes = {}
  end

  def records
    self.class.models.flat_map do |name, model|
      scope_for(name).map do |record|
        { type: "BackupRecord", data: { model: name, attributes: attributes_for(record, model) } }
      end
    end
  end

  def attachments
    self.class.models.flat_map do |name, model|
      next [] unless self.class.has_attachments?(model)

      ActiveStorage::Attachment.includes(:blob)
        .where(record_type: model.base_class.name, record_id: scope_for(name).select(:id))
        .map do |attachment|
          blob = attachment.blob
          bytes = blob.download
          unless bytes.bytesize == blob.byte_size && Digest::MD5.base64digest(bytes) == blob.checksum
            raise InvalidBackupError, "Attachment #{attachment.id} failed its integrity check"
          end
          {
            type: "BackupAttachment",
            data: {
              id: attachment.id, model: name, record_id: attachment.record_id,
              name: attachment.name, filename: blob.filename.to_s,
              content_type: blob.content_type, metadata: blob.metadata,
              byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes),
              created_at: attachment.created_at.iso8601(6), blob_created_at: blob.created_at.iso8601(6), content: Base64.strict_encode64(bytes)
            }
          }
        end
    end
  end

  def generate_ndjson
    payload = (records + attachments).map(&:to_json).join("\n")
    manifest = {
      type: "BackupManifest",
      data: { version: VERSION, family_id: @family.id, sha256: Digest::SHA256.hexdigest(payload) }
    }
    [ manifest.to_json, payload ].join("\n")
  end

  def report
    missing = @family.family_documents.where("file_size > 0")
      .where.not(id: ActiveStorage::Attachment.where(record_type: "FamilyDocument", name: "file").select(:record_id))
      .map { |document| { id: document.id, filename: document.filename, byte_size: document.file_size } }
    {
      snapshot_version: VERSION,
      excluded_tables: EXCLUDED_FAMILY_TABLES,
      excluded_attributes: EXCLUDED_ATTRIBUTES,
      unavailable_document_originals: missing
    }
  end

  def scope_for(name)
    @scopes[name] ||= build_scope(name)
  end

  private
    def attributes_for(record, model)
      record.attributes.except(*(EXCLUDED_ATTRIBUTES[model.name] || [])).transform_values do |value|
        value.respond_to?(:iso8601) && !value.is_a?(Date) ? value.iso8601(6) : value
      end
    end

    def build_scope(name)
      model = self.class.models.fetch(name)
      return model.where(id: @family.id) if name == "Family"
      return model.where(family_id: @family.id) if model.column_names.include?("family_id") && name != "Merchant"

      case name
      when "Merchant"
        ids = @family.transactions.pluck(:merchant_id) + @family.recurring_transactions.pluck(:merchant_id) +
          @family.scheduled_payments.pluck(:merchant_id) + @family.merchant_customizations.pluck(:merchant_id) +
          FamilyMerchantAssociation.where(family_id: @family.id).pluck(:merchant_id)
        ids += Rule::Action.where(rule_id: @family.rules.select(:id), action_type: "set_transaction_merchant").pluck(:value)
        ids += Rule::Condition.where(rule_id: @family.rules.select(:id), condition_type: "transaction_merchant").pluck(:value)
        model.where(family_id: @family.id).or(model.where(id: ids.compact))
      when "Security"
        model.where(id: @family.holdings.select(:security_id)).or(model.where(id: @family.trades.select(:security_id)))
      when "ExchangeRate", "ExchangeRatePair"
        currencies = [ @family.currency, "USD", *@family.enabled_currencies,
          *@family.accounts.distinct.pluck(:currency), *@family.entries.distinct.pluck(:currency),
          *@family.holdings.distinct.pluck(:currency), *@family.goals.distinct.pluck(:currency),
          *Security::Price.where(security_id: scope_for("Security").select(:id)).distinct.pluck(:currency) ].compact.uniq
        model.where(from_currency: currencies, to_currency: currencies)
      when "Transaction", "Trade", "Valuation"
        model.where(id: @family.entries.where(entryable_type: name).select(:entryable_id))
      when *Family::DataImporter::ACCOUNTABLE_TYPE_CLASSES.keys
        model.where(id: @family.accounts.where(accountable_type: name).select(:accountable_id))
      when "Transfer", "RejectedTransfer"
        model.where(inflow_transaction_id: scope_for("Transaction").select(:id), outflow_transaction_id: scope_for("Transaction").select(:id))
      when "Address", "Tagging", "DataEnrichment"
        association = model.reflect_on_all_associations(:belongs_to).find(&:polymorphic?)
        POLYMORPHIC_PARENTS.fetch(name).reduce(model.none) do |scope, parent_name|
          parent = self.class.models.fetch(parent_name)
          scope.or(model.where(association.foreign_type => parent.base_class.name, association.foreign_key => scope_for(parent_name).select(:id)))
        end
      else
        parent, foreign_key = PARENTS.fetch(name)
        model.where(foreign_key => scope_for(parent).select(:id))
      end
    end
end
