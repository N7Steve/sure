require "test_helper"

class GoogleDriveConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
  end

  test "connect starts a separate offline OAuth flow" do
    GoogleDrive::Client.stubs(:configured?).returns(true)
    GoogleDrive::Client.stubs(:generate_pkce).returns(verifier: "verifier", challenge: "challenge")
    GoogleDrive::Client.expects(:authorization_url).with do |attributes|
      attributes[:state].present? && attributes[:code_challenge] == "challenge"
    end.returns("https://accounts.google.com/o/oauth2/v2/auth?client_id=test")

    post connect_google_drive_connection_path

    assert_redirected_to "https://accounts.google.com/o/oauth2/v2/auth?client_id=test"
    assert_equal @user.id, session.dig(:google_drive_oauth, "user_id")
    assert_equal "verifier", session.dig(:google_drive_oauth, "code_verifier")
  end

  test "callback rejects a mismatched state" do
    GoogleDrive::Client.expects(:exchange_code).never

    get callback_google_drive_connection_path, params: { code: "code", state: "invalid" }

    assert_redirected_to family_exports_path
    assert flash[:alert].present?
  end

  test "callback stores the connected Google identity and tokens" do
    GoogleDrive::Client.stubs(:configured?).returns(true)
    GoogleDrive::Client.stubs(:generate_pkce).returns(verifier: "verifier", challenge: "challenge")
    GoogleDrive::Client.stubs(:authorization_url).returns("https://accounts.google.com/authorize")
    post connect_google_drive_connection_path
    oauth_session = session[:google_drive_oauth]

    GoogleDrive::Client.expects(:exchange_code).returns(
      "access_token" => "access-token",
      "refresh_token" => "refresh-token",
      "expires_in" => 3600,
      "scope" => "openid email https://www.googleapis.com/auth/drive.file"
    )
    GoogleDrive::Client.expects(:user_info).with(access_token: "access-token").returns(
      "sub" => "google-subject",
      "email" => "personal@example.com"
    )

    get callback_google_drive_connection_path, params: { code: "code", state: oauth_session["state"] }

    assert_redirected_to family_exports_path
    connection = @user.reload.google_drive_connection
    assert_equal "google-subject", connection.google_subject
    assert_equal "personal@example.com", connection.email
    assert_equal "refresh-token", connection.refresh_token
    assert_nil session[:google_drive_oauth]
  end

  test "filters OAuth codes without hiding unrelated code fields" do
    parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = parameter_filter.filter(code: "authorization-code", country_code: "ES")

    assert_equal "[FILTERED]", filtered[:code]
    assert_equal "ES", filtered[:country_code]
  end
end
