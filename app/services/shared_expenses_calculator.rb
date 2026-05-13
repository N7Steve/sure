# app/services/shared_expenses_calculator.rb
# TEMPORARY: Shared expenses calculator - can be fully removed in the future
# See rollback_gc.md for removal instructions
class SharedExpensesCalculator
  TAG_NAME = "Gastos compartidos"
  RENT_CATEGORY_NAME = "Rentas de trabajo"

  def initialize(family)
    @family = family
  end

  # Calculates pending debt from all-time shared expenses
  def calculate_debt
    tag = @family.tags.find_by(name: TAG_NAME)
    return { pending_debt: zero_money, has_data: false } unless tag

    tagged_transactions = base_tagged_scope(tag)
    family_currency = @family.currency

    total_expenses = 0
    total_income = 0

    tagged_transactions.includes(:entry).find_each do |txn|
      converted = convert_amount(txn.entry.amount, txn.entry.currency, family_currency)
      if txn.entry.amount > 0
        total_expenses += converted
      else
        total_income += converted.abs
      end
    end

    half_expenses = total_expenses / 2.0
    pending_debt = [half_expenses - total_income, 0].max

    {
      pending_debt: Money.new(pending_debt, family_currency),
      has_data: total_expenses > 0 || total_income > 0
    }
  end

  # Calculates adjusted expenses for a given period:
  # expenses_without_shared_tag + (expenses_with_shared_tag / 2)
  def calculate_adjusted_expenses(period)
    tag = @family.tags.find_by(name: TAG_NAME)
    family_currency = @family.currency
    date_range = period.date_range

    # All expense transactions in the period (amount > 0)
    all_expenses_scope = expense_transactions_scope(date_range)

    if tag.nil?
      # No shared tag exists: all expenses count as-is
      total = sum_expenses(all_expenses_scope, family_currency)
      return Money.new(total, family_currency)
    end

    # Shared expense transactions (tagged)
    shared_scope = all_expenses_scope
      .joins(:taggings)
      .where(taggings: { tag_id: tag.id })

    shared_total = sum_expenses(shared_scope, family_currency)

    # Non-shared = all - shared
    all_total = sum_expenses(all_expenses_scope, family_currency)
    non_shared_total = all_total - shared_total

    adjusted = non_shared_total + (shared_total / 2.0)
    Money.new(adjusted, family_currency)
  end

  # Calculates income only from the "Rentas de trabajo" category for a given period
  def calculate_rent_income(period)
    family_currency = @family.currency
    date_range = period.date_range

    category = @family.categories.find_by(name: RENT_CATEGORY_NAME)
    return zero_money unless category

    # Include the category itself and all its subcategories
    category_ids = [category.id] + @family.categories.where(parent_id: category.id).pluck(:id)

    # Income transactions: amount < 0, in the given category
    income_scope = Transaction
      .joins(:entry)
      .joins(entry: :account)
      .where(accounts: { family_id: @family.id })
      .where(entries: { entryable_type: "Transaction", excluded: false, date: date_range })
      .where(category_id: category_ids)
      .where("entries.amount < 0")

    total = 0
    income_scope.includes(:entry).find_each do |txn|
      total += convert_amount(txn.entry.amount, txn.entry.currency, family_currency).abs
    end

    Money.new(total, family_currency)
  end

  private

  def zero_money
    Money.new(0, @family.currency)
  end

  def base_tagged_scope(tag)
    Transaction
      .joins(:entry)
      .joins(entry: :account)
      .joins(:taggings)
      .where(accounts: { family_id: @family.id })
      .where(taggings: { tag_id: tag.id })
      .where(entries: { entryable_type: "Transaction", excluded: false })
  end

  def expense_transactions_scope(date_range)
    Transaction
      .joins(:entry)
      .joins(entry: :account)
      .where(accounts: { family_id: @family.id })
      .where(entries: { entryable_type: "Transaction", excluded: false, date: date_range })
      .where("entries.amount > 0")
  end

  def sum_expenses(scope, family_currency)
    total = 0
    scope.includes(:entry).find_each do |txn|
      total += convert_amount(txn.entry.amount, txn.entry.currency, family_currency)
    end
    total
  end

  def convert_amount(amount, currency, target_currency)
    Money.new(amount, currency).exchange_to(target_currency).amount
  rescue Money::ConversionError
    amount
  end
end
