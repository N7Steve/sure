# app/services/shared_expenses_calculator.rb
# TEMPORARY: Shared expenses calculator - can be fully removed in the future
# See rollback_gc.md for removal instructions
class SharedExpensesCalculator
  TAG_NAME = "Gastos compartidos"

  def initialize(family)
    @family = family
  end

  def calculate
    tag = @family.tags.find_by(name: TAG_NAME)
    return empty_result unless tag

    # Get ALL transactions (full history) tagged with "Gastos compartidos"
    tagged_transactions = Transaction
      .joins(:entry)
      .joins(entry: :account)
      .joins(:taggings)
      .where(accounts: { family_id: @family.id })
      .where(taggings: { tag_id: tag.id })
      .where(entries: { entryable_type: "Transaction", excluded: false })

    family_currency = @family.currency

    total_expenses = 0
    total_income = 0

    tagged_transactions.includes(:entry).find_each do |txn|
      amount = txn.entry.amount
      if amount > 0
        # Gasto (expense): amount is positive
        begin
          converted = Money.new(amount, txn.entry.currency).exchange_to(family_currency).amount
        rescue Money::ConversionError
          converted = amount
        end
        total_expenses += converted
      else
        # Ingreso (income): amount is negative, take absolute value
        begin
          converted = Money.new(amount.abs, txn.entry.currency).exchange_to(family_currency).amount
        rescue Money::ConversionError
          converted = amount.abs
        end
        total_income += converted
      end
    end

    half_expenses = total_expenses / 2.0
    pending_debt = half_expenses - total_income
    pending_debt = 0 if pending_debt < 0

    {
      pending_debt: Money.new(pending_debt, family_currency),
      has_data: total_expenses > 0 || total_income > 0
    }
  end

  private

  def empty_result
    currency = @family.currency
    {
      pending_debt: Money.new(0, currency),
      has_data: false
    }
  end
end
