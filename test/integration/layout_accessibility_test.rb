require "test_helper"

class LayoutAccessibilityTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "application layout renders skip-link pointing at #main and a <main> with id=\"main\"" do
    get root_path
    assert_response :ok

    skip_text = I18n.t("layouts.application.skip_to_main")

    assert_select "a[href=\"#main\"]", text: skip_text
    assert_select "main#main"
  end

  test "application layout opts into same-origin view transitions" do
    get root_path
    assert_response :ok

    assert_select 'meta[name="view-transition"][content="same-origin"]', count: 1
  end

  test "account sidebar groups persist and animate their disclosure state" do
    get root_path
    assert_response :ok

    assert_select "#account-sidebar-tabs details[data-controller~='persisted-disclosure'][data-controller~='DS--disclosure']"
    assert_select "#account-sidebar-tabs details[data-persisted-disclosure-key-value]"
  end

  test "settings layout renders skip-link pointing at #main and a <main> with id=\"main\"" do
    get settings_profile_path
    assert_response :ok

    skip_text = I18n.t("layouts.application.skip_to_main")

    assert_select "a[href=\"#main\"]", text: skip_text
    assert_select "main#main"
  end
end
