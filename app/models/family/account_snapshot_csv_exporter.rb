require "csv"

class Family::AccountSnapshotCsvExporter
  Result = Data.define(:io, :record_count)

  HEADERS = %w[
    snapshot_date position_id institution name type subtype scope value currency notes
  ].freeze

  POSITION_TYPES = {
    "Depository" => "cash",
    "Investment" => "investment",
    "Crypto" => "investment",
    "OtherAsset" => "receivable",
    "Property" => "property",
    "Vehicle" => "property",
    "CreditCard" => "liability",
    "Loan" => "liability",
    "OtherLiability" => "liability"
  }.freeze

  SUBTYPE_ALIASES = {
    "Depository" => {
      "checking" => "checking_account",
      "savings" => "savings_account",
      "payroll" => "payroll_account",
      "mortgage" => "mortgage_account",
      "investment" => "investment_account",
      "asset" => "asset_account",
      "hsa" => "health_savings_account",
      "cd" => "certificate_of_deposit",
      "money_market" => "money_market_account"
    },
    "Loan" => {
      "student" => "student_loan",
      "auto" => "car_loan",
      "home_equity" => "home_equity_loan",
      "business" => "business_loan",
      "other" => "personal_loan"
    }
  }.freeze

  DEFAULT_SUBTYPES = {
    "Depository" => "cash_account",
    "Investment" => "investment_account",
    "Crypto" => "crypto",
    "OtherAsset" => "receivable",
    "Property" => "property",
    "Vehicle" => "vehicle",
    "CreditCard" => "credit_card",
    "Loan" => "loan",
    "OtherLiability" => "other_liability"
  }.freeze

  def initialize(schedule)
    @schedule = schedule
    @user = schedule.requested_by
  end

  def generate
    selected_accounts = accounts.to_a
    csv_data = CSV.generate(col_sep: ",") do |csv|
      csv << HEADERS
      selected_accounts.each { |account| csv << serialize(account) }
    end

    Result.new(io: StringIO.new(csv_data), record_count: selected_accounts.size)
  end

  private
    attr_reader :schedule, :user

    def accounts
      user.accessible_accounts
        .where(id: schedule.selected_account_ids)
        .includes(:accountable, account_providers: :provider)
        .order(:name, :id)
    end

    def serialize(account)
      [
        schedule.export_end_date.iso8601,
        account.id,
        spreadsheet_safe(account.institution_name),
        spreadsheet_safe(account.name),
        POSITION_TYPES.fetch(account.accountable_type),
        position_subtype(account),
        account.financial_treatment,
        account.balance.to_d.abs.to_s("F"),
        account.currency,
        spreadsheet_safe(account.notes)
      ]
    end

    def position_subtype(account)
      normalized = account.subtype.to_s.parameterize(separator: "_").presence
      SUBTYPE_ALIASES.fetch(account.accountable_type, {}).fetch(
        normalized,
        normalized || DEFAULT_SUBTYPES.fetch(account.accountable_type)
      )
    end

    def spreadsheet_safe(value)
      string = value.to_s
      return if string.empty?

      string.match?(/\A[=+\-@]/) ? "'#{string}" : string
    end
end
