require "test_helper"

class MerchantCustomizationTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @other_family = families(:empty)
    @merchant = ProviderMerchant.create!(
      name: "Shared provider merchant",
      source: "plaid",
      logo_url: "https://example.com/provider-logo.png"
    )
  end

  test "custom logos are isolated by family" do
    customization = MerchantCustomization.create!(family: @family, merchant: @merchant)
    customization.custom_logo.attach(
      io: file_fixture("profile_image.png").open,
      filename: "custom.png",
      content_type: "image/png"
    )

    assert_includes @merchant.display_logo_url(family: @family), "/rails/active_storage/representations/"
    assert_equal "https://example.com/provider-logo.png", @merchant.display_logo_url(family: @other_family)
  end

  test "family merchant customization must belong to the same family" do
    customization = MerchantCustomization.new(
      family: @other_family,
      merchant: merchants(:netflix)
    )

    assert_not customization.valid?
    assert customization.errors[:merchant].present?
  end

  test "rejects unsupported custom logo formats" do
    customization = MerchantCustomization.new(family: @family, merchant: @merchant)
    customization.custom_logo.attach(
      io: StringIO.new("not an image"),
      filename: "custom.svg",
      content_type: "image/svg+xml"
    )

    assert_not customization.valid?
    assert customization.errors[:custom_logo].present?
  end
end
