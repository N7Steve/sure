require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @budget = budgets(:one)
  end

  test "destroy deletes the budget and redirects to index" do
    assert_difference("Budget.count", -1) do
      delete budget_path(@budget)
    end

    assert_redirected_to budgets_path
    assert_equal "Budget deleted successfully", flash[:notice]
  end

  test "destroy also deletes associated budget_categories" do
    categories_count = @budget.budget_categories.count
    assert categories_count.positive?, "fixture must have budget categories"

    assert_difference("BudgetCategory.count", -categories_count) do
      delete budget_path(@budget)
    end
  end

  test "destroy returns 404 for a budget that does not exist" do
    delete budget_path("jan-1900")
    assert_response :not_found
  end

  test "destroy is not accessible without authentication" do
    sign_out
    delete budget_path(@budget)
    assert_redirected_to new_session_path
  end
end
