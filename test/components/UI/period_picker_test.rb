require "test_helper"

class UI::PeriodPickerTest < ViewComponent::TestCase
  test "renders one menuitemradio link per period, all carrying the period param and target frame" do
    render_inline(UI::PeriodPicker.new(selected: "last_30_days", url: "/", frame: "dashboard_sections"))

    links = page.all("a[role='menuitemradio']")
    assert_equal Period.all.size, links.size

    links.each do |link|
      assert_match(/period=/, link[:href])
      assert_equal "dashboard_sections", link["data-turbo-frame"]
    end
  end

  test "marks the selected period with aria-checked and a check glyph" do
    render_inline(UI::PeriodPicker.new(selected: "last_90_days", url: "/", frame: "dashboard_sections"))

    selected = page.all("a[role='menuitemradio'][aria-checked='true']")
    assert_equal 1, selected.size
    assert_match(/period=last_90_days/, selected.first[:href])
    # Check icon (svg) renders inside the selected item only.
    assert_selector "a[aria-checked='true'] svg"
  end

  test "trigger button shows the selected period's short label" do
    render_inline(UI::PeriodPicker.new(selected: "last_30_days", url: "/"))

    assert_text Period.from_key("last_30_days").label_short
  end

  test "trigger accessible name announces the selected period" do
    render_inline(UI::PeriodPicker.new(selected: "last_90_days", url: "/"))

    label = Period.from_key("last_90_days").label_short
    assert_selector "button[aria-label='Time period: #{label}']"
  end

  test "extra_params are merged into every option href" do
    render_inline(UI::PeriodPicker.new(
      selected: "last_30_days",
      url: "/accounts/abc",
      extra_params: { chart_view: "balance" }
    ))

    href = page.first("a[role='menuitemradio']")[:href]
    assert_match(%r{\A/accounts/abc\?}, href)
    assert_match(/chart_view=balance/, href)
    assert_match(/period=/, href)
  end

  test "supports a custom query parameter" do
    render_inline(UI::PeriodPicker.new(
      selected: "last_30_days",
      url: "/",
      param: :net_worth_chart_period
    ))

    href = page.first("a[role='menuitemradio']")[:href]
    assert_match(/net_worth_chart_period=/, href)
    assert_no_match(/[?&]period=/, href)
  end

  test "supports a contextual accessible label" do
    render_inline(UI::PeriodPicker.new(
      selected: "last_5_years",
      url: "/",
      aria_label: "Net Worth time period: 5Y"
    ))

    assert_selector "button[aria-label='Net Worth time period: 5Y']"
  end

  test "accepts a Period object as selected" do
    render_inline(UI::PeriodPicker.new(selected: Period.last_7_days, url: "/"))

    assert_text Period.from_key("last_7_days").label_short
    assert_equal 1, page.all("a[aria-checked='true']").size
  end
end
