require "test_helper"

class TransactionCategoriesControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:family_admin)
    @entry = entries(:transaction)
    @transaction = @entry.transaction
  end

  test "updates the category and refreshes the inline category menus" do
    category = categories(:income)

    patch transaction_category_url(@entry),
          params: {
            entry: {
              entryable_type: "Transaction",
              entryable_attributes: {
                id: @transaction.id,
                category_id: category.id
              }
            }
          },
          as: :turbo_stream

    assert_response :success
    assert_equal category, @transaction.reload.category
    assert_select "turbo-stream[action='replace'][target='#{dom_id(@transaction, "category_menu_mobile")}']"
    assert_select "turbo-stream[action='replace'][target='#{dom_id(@transaction, "category_menu_desktop")}']"
  end
end
