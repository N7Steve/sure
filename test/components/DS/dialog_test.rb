require "test_helper"

class DS::DialogTest < ViewComponent::TestCase
  test "renders separate animation targets for the backdrop and content" do
    render_inline(DS::Dialog.new(auto_open: false, disable_frame: true)) do |dialog|
      dialog.with_body { "Dialog body" }
    end

    assert_selector "dialog[data-controller~='DS--dialog']"
    assert_selector "dialog > [data-DS--dialog-target='backdrop']"
    assert_selector "dialog [data-DS--dialog-target='content']", text: "Dialog body"
  end
end
