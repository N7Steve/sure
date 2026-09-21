require "csv"

class Family::TransactionCsvExporter
  Result = Data.define(:io, :record_count)

  UTF_8_BOM = "\uFEFF"
  SEMICOLON_LANGUAGES = %w[ca de es fr hu it nb nl pl pt ro ru tr uk vi].freeze
  HEADERS = %w[source_account destination_account merchant title amount date category tags].freeze
  DRIVE_HEADERS = %w[
    entry_id transaction_id source_account_id source_account destination_account_id
    destination_account merchant title amount currency date category tags updated_at
  ].freeze
  DRIVE_CLEAN_HEADERS = %w[
    transaction_id source_account destination_account merchant title type amount currency
    date category subcategory tags
  ].freeze

  def initialize(family_export, schema: :manual)
    @family_export = family_export
    @family = family_export.family
    @user = family_export.requested_by
    @schema = schema
  end

  def generate
    count = 0
    csv_data = CSV.generate(col_sep: column_separator) do |csv|
      csv << headers

      export_transactions.each do |transaction|
        csv << serialize(transaction)
        count += 1
      end
    end

    content = clean_drive_schema? ? csv_data : "#{UTF_8_BOM}#{csv_data}"
    Result.new(io: StringIO.new(content), record_count: count)
  end

  private
    attr_reader :family_export, :family, :user, :schema

    def headers
      return HEADERS unless schema == :drive

      selected_headers = drive_detailed? ? DRIVE_HEADERS : DRIVE_CLEAN_HEADERS
      unless include_category_column?
        selected_headers = selected_headers.reject { |header| %w[category subcategory].include?(header) }
      end
      selected_headers = selected_headers.reject { |header| header == "tags" } unless include_tags_column?
      selected_headers
    end

    def export_transactions
      return transactions unless clean_drive_schema?

      seen_transfer_ids = {}
      transactions.filter_map do |transaction|
        transfer = transaction.transfer
        next transaction unless transfer
        next if seen_transfer_ids[transfer.id]

        seen_transfer_ids[transfer.id] = true
        transaction
      end
    end

    def transactions
      @transactions ||= begin
        scope = Transaction
          .joins(entry: :account)
          .where(accounts: { family_id: family.id })
          .merge(Entry.excluding_split_parents)
          .where(entries: {
            account_id: accessible_selected_account_ids,
            date: export_start_date..export_end_date
          })

        scope = exclude_categories(scope)
        scope = exclude_tags(scope)

        scope
          .merge(Entry.chronological)
          .includes(
            :tags,
            :merchant,
            { category: :parent },
            { entry: :account },
            {
              transfer_as_inflow: {
                outflow_transaction: [ :tags, :merchant, { category: :parent }, { entry: :account } ]
              }
            },
            {
              transfer_as_outflow: {
                inflow_transaction: [ :tags, :merchant, { category: :parent }, { entry: :account } ]
              }
            }
          )
      end
    end

    def accessible_selected_account_ids
      @accessible_selected_account_ids ||= begin
        ids = user.accessible_accounts
          .where(id: family_export.selected_account_ids)
          .pluck(:id)

        raise ArgumentError, "No selected accounts are accessible to the export requester" if ids.empty?

        ids
      end
    end

    def export_start_date
      return family_export.export_start_date if family_export.respond_to?(:export_start_date)

      family_export.start_date
    end

    def export_end_date
      return family_export.export_end_date if family_export.respond_to?(:export_end_date)

      family_export.end_date
    end

    def exclude_categories(scope)
      selected_ids = family.categories.where(id: family_export.excluded_category_ids).pluck(:id)
      return scope if selected_ids.empty?

      category_ids = family.categories
        .where(id: selected_ids)
        .or(family.categories.where(parent_id: selected_ids))
        .pluck(:id)

      excluded_ids = Transaction.where(category_id: category_ids).select(:id)
      scope.where.not(id: excluded_ids)
    end

    def exclude_tags(scope)
      tag_ids = family.tags.where(id: family_export.excluded_tag_ids).pluck(:id)
      return scope if tag_ids.empty?

      excluded_ids = Transaction.joins(:taggings)
        .where(taggings: { tag_id: tag_ids })
        .select(:id)

      scope.where.not(id: excluded_ids)
    end

    def serialize(transaction)
      entry = transaction.entry
      transfer = transaction.transfer

      return serialize_for_drive(transaction, entry, transfer) if schema == :drive

      [
        spreadsheet_safe(account_name(transfer&.from_account || entry.account)),
        spreadsheet_safe(account_name(transfer&.to_account)),
        spreadsheet_safe(transaction.merchant&.name),
        spreadsheet_safe(entry.name),
        amount_value(entry.amount),
        entry.date&.iso8601,
        spreadsheet_safe(category_name(transaction.category)),
        spreadsheet_safe(transaction.tags.map(&:name).sort.join(", "))
      ]
    end

    def serialize_for_drive(transaction, entry, transfer)
      return serialize_clean_for_drive(transaction, entry, transfer) if clean_drive_schema?

      source_account = transfer&.from_account || entry.account
      destination_account = transfer&.to_account

      values = {
        "entry_id" => entry.id,
        "transaction_id" => transaction.id,
        "source_account_id" => accessible_account_id(source_account),
        "source_account" => spreadsheet_safe(account_name(source_account)),
        "destination_account_id" => accessible_account_id(destination_account),
        "destination_account" => spreadsheet_safe(account_name(destination_account)),
        "merchant" => spreadsheet_safe(transaction.merchant&.name),
        "title" => spreadsheet_safe(entry.name),
        "amount" => amount_value(entry.amount),
        "currency" => entry.currency,
        "date" => entry.date&.iso8601,
        "category" => spreadsheet_safe(category_name(transaction.category)),
        "tags" => spreadsheet_safe(transaction.tags.map(&:name).sort.join(", ")),
        "updated_at" => entry.updated_at&.iso8601
      }

      headers.map { |header| values.fetch(header) }
    end

    def serialize_clean_for_drive(transaction, entry, transfer)
      if transfer
        outflow_transaction = transaction.id == transfer.outflow_transaction_id ? transaction : transfer.outflow_transaction
        inflow_transaction = transaction.id == transfer.inflow_transaction_id ? transaction : transfer.inflow_transaction
        entry = outflow_transaction.entry
        source_account = entry.account
        destination_account = inflow_transaction.entry.account
        category = outflow_transaction.category || inflow_transaction.category
        tag_names = (outflow_transaction.tags.to_a + inflow_transaction.tags.to_a).map(&:name).uniq.sort
        merchant = outflow_transaction.merchant || inflow_transaction.merchant
        transaction_id = transfer.id
        title = entry.name.presence || transfer.name
      else
        source_account = entry.amount.negative? ? nil : entry.account
        destination_account = entry.amount.negative? ? entry.account : nil
        category = transaction.category
        tag_names = transaction.tags.map(&:name).sort
        merchant = transaction.merchant
        transaction_id = transaction.id
        title = entry.name
      end

      values = {
        "transaction_id" => transaction_id,
        "source_account" => spreadsheet_safe(account_name(source_account)),
        "destination_account" => spreadsheet_safe(account_name(destination_account)),
        "merchant" => spreadsheet_safe(merchant&.name),
        "title" => spreadsheet_safe(title),
        "type" => clean_transaction_type(transaction),
        "amount" => entry.amount.to_d.abs.to_s("F"),
        "currency" => entry.currency,
        "date" => entry.date&.iso8601,
        "category" => spreadsheet_safe(top_level_category_name(category)),
        "subcategory" => spreadsheet_safe(subcategory_name(category)),
        "tags" => spreadsheet_safe(tag_names.join(", "))
      }

      headers.map { |header| values.fetch(header) }
    end

    def clean_transaction_type(transaction)
      return "transfer" if transaction.transfer? || transaction.transfer.present?

      transaction.entry.amount.negative? ? "income" : "expense"
    end

    def drive_detailed?
      return true unless family_export.respond_to?(:detailed_export?)

      family_export.detailed_export?
    end

    def clean_drive_schema?
      schema == :drive && !drive_detailed?
    end

    def include_category_column?
      return true unless family_export.respond_to?(:include_category_column?)

      family_export.include_category_column?
    end

    def include_tags_column?
      return true unless family_export.respond_to?(:include_tags_column?)

      family_export.include_tags_column?
    end

    def account_name(account)
      return if account.blank? || !accessible_account_ids.include?(account.id)

      account.name
    end

    def accessible_account_id(account)
      account.id if account.present? && accessible_account_ids.include?(account.id)
    end

    def accessible_account_ids
      @accessible_account_ids ||= user.accessible_accounts.pluck(:id)
    end

    def category_name(category)
      return if category.blank?

      [ category.parent&.name, category.name ].compact.join(" / ")
    end

    def top_level_category_name(category)
      category&.parent&.name || category&.name
    end

    def subcategory_name(category)
      category&.name if category&.parent
    end

    def column_separator
      return "," if clean_drive_schema?

      locale = user.locale.presence || family.locale.presence || I18n.default_locale.to_s
      SEMICOLON_LANGUAGES.include?(locale.to_s.tr("_", "-").split("-").first) ? ";" : ","
    end

    def amount_value(amount)
      column_separator == ";" ? amount.to_s.tr(".", ",") : amount.to_s
    end

    def spreadsheet_safe(value)
      string = value.to_s
      return if string.empty?

      string.match?(/\A[=+\-@]/) ? "'#{string}" : string
    end
end
