require "csv"

class Family::TransactionCsvExporter
  Result = Data.define(:io, :record_count)

  UTF_8_BOM = "\uFEFF"
  SEMICOLON_LANGUAGES = %w[ca de es fr hu it nb nl pl pt ro ru tr uk vi].freeze
  HEADERS = %w[source_account destination_account merchant title amount date category tags].freeze

  def initialize(family_export)
    @family_export = family_export
    @family = family_export.family
    @user = family_export.requested_by
  end

  def generate
    count = 0
    csv_data = CSV.generate(col_sep: column_separator) do |csv|
      csv << HEADERS

      transactions.each do |transaction|
        csv << serialize(transaction)
        count += 1
      end
    end

    Result.new(io: StringIO.new("#{UTF_8_BOM}#{csv_data}"), record_count: count)
  end

  private
    attr_reader :family_export, :family, :user

    def transactions
      @transactions ||= begin
        scope = Transaction
          .joins(entry: :account)
          .where(accounts: { family_id: family.id })
          .merge(Entry.excluding_split_parents)
          .where(entries: {
            account_id: accessible_selected_account_ids,
            date: family_export.start_date..family_export.end_date
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
            { transfer_as_inflow: { outflow_transaction: { entry: :account } } },
            { transfer_as_outflow: { inflow_transaction: { entry: :account } } }
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

    def account_name(account)
      return if account.blank? || !accessible_account_ids.include?(account.id)

      account.name
    end

    def accessible_account_ids
      @accessible_account_ids ||= user.accessible_accounts.pluck(:id)
    end

    def category_name(category)
      return if category.blank?

      [ category.parent&.name, category.name ].compact.join(" / ")
    end

    def column_separator
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
