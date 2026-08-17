require "csv"

class Family::TransactionCsvExporter
  Result = Data.define(:io, :record_count)

  HEADERS = %w[
    date transaction_id entry_id account account_id name merchant amount currency
    transaction_type parent_category category tags notes status excluded kind
    transfer_id transfer_direction counterparty_account split_parent_id
  ].freeze

  def initialize(family_export)
    @family_export = family_export
    @family = family_export.family
    @user = family_export.requested_by
  end

  def generate
    count = 0
    csv_data = CSV.generate do |csv|
      csv << HEADERS

      transactions.each do |transaction|
        csv << serialize(transaction)
        count += 1
      end
    end

    Result.new(io: StringIO.new(csv_data), record_count: count)
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
            { entry: [ :account, :parent_entry ] },
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
        entry.date&.iso8601,
        transaction.id,
        entry.id,
        spreadsheet_safe(entry.account.name),
        entry.account_id,
        spreadsheet_safe(entry.name),
        spreadsheet_safe(transaction.merchant&.name),
        entry.amount.to_s,
        entry.currency,
        transaction_type(transaction),
        spreadsheet_safe(transaction.category&.parent&.name),
        spreadsheet_safe(transaction.category&.name),
        spreadsheet_safe(transaction.tags.map(&:name).sort.join(", ")),
        spreadsheet_safe(entry.notes),
        transaction.pending? ? "pending" : "confirmed",
        entry.excluded?,
        transaction.kind,
        transfer&.id,
        transfer_direction(transaction, transfer),
        spreadsheet_safe(counterparty_account_name(transaction, transfer)),
        entry.parent_entry_id
      ]
    end

    def transaction_type(transaction)
      return "transfer" if transaction.transfer?

      transaction.entry.amount.negative? ? "income" : "expense"
    end

    def transfer_direction(transaction, transfer)
      return if transfer.blank?

      transfer.inflow_transaction_id == transaction.id ? "inflow" : "outflow"
    end

    def counterparty_account_name(transaction, transfer)
      return if transfer.blank?

      counterpart = if transfer.inflow_transaction_id == transaction.id
        transfer.outflow_transaction
      else
        transfer.inflow_transaction
      end

      counterpart&.entry&.account&.name
    end

    def spreadsheet_safe(value)
      string = value.to_s
      return if string.empty?

      string.match?(/\A[=+\-@]/) ? "'#{string}" : string
    end
end
