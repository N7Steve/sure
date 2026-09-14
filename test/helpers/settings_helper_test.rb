# frozen_string_literal: true

require "test_helper"

class SettingsHelperTest < ActionView::TestCase
  setup do
    Current.session = sessions(:one)
    self.stubs(:self_hosted?).returns(false)
    self.stubs(:ai_features_enabled?).returns(true)
  end

  teardown do
    Current.reset
  end

  test "settings navigation groups related data tasks and shares one visible order" do
    sections = settings_nav_sections

    assert_equal [
      "Personal & family",
      "Accounts & data",
      "Organization",
      "Integrations",
      "Help"
    ], sections.pluck(:header)

    accounts_and_data = sections.find { |section| section[:header] == "Accounts & data" }
    assert_equal [
      "Accounts",
      "Bank sync",
      "Imports",
      "Statement Vault",
      "Exports"
    ], accounts_and_data[:items].pluck(:label)
  end

  test "settings navigation hides admin groups and actions from members" do
    Current.session = Session.create!(user: users(:family_member))

    sections = settings_nav_sections
    labels = sections.flat_map { |section| section[:items].pluck(:label) }

    assert_not_includes sections.pluck(:header), "Integrations"
    assert_not_includes sections.pluck(:header), "System"
    assert_not_includes labels, "Bank sync"
    assert_not_includes labels, "Imports"
    assert_not_includes labels, "Statement Vault"
    assert_includes labels, "Exports"
  end

  test "settings navigation presents instance administration under system" do
    Current.session = Session.create!(user: users(:sure_support_staff))
    self.stubs(:self_hosted?).returns(true)

    system_section = settings_nav_sections.find { |section| section[:header] == "System" }

    assert_equal [
      "Instance users",
      "SSO Providers",
      "Instance settings",
      "System health",
      "Background jobs",
      "Debug"
    ], system_section[:items].pluck(:label)
  end

  test "provider_summary for snaptrade is off when family has no snaptrade items" do
    @snaptrade_items = []

    assert_equal({ status: :off }, provider_summary("snaptrade"))
  end

  test "provider_summary for snaptrade is off when no item has completed OAuth" do
    item = OpenStruct.new(oauth_configured?: false)
    @snaptrade_items = [ item ]

    assert_equal({ status: :off }, provider_summary("snaptrade"))
  end

  test "provider_summary for snaptrade reports sync-based status once an item is oauth configured" do
    item = OpenStruct.new(oauth_configured?: true)
    @snaptrade_items = [ item ]
    @provider_sync_health = {}

    assert_equal({ status: :ok, last_synced_at: nil }, provider_summary("snaptrade"))
  end

  test "provider_summary for trading212 reports sync-based status when connected" do
    @trading212_items = [ OpenStruct.new ]
    @provider_sync_health = {}

    assert_equal({ status: :ok, last_synced_at: nil }, provider_summary("trading212"))
  end

  test "provider_summary for trading212 is off without connections" do
    @trading212_items = []

    assert_equal({ status: :off }, provider_summary("trading212"))
  end
end
