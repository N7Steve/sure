require "test_helper"

class GoogleDriveConnectionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @connection = GoogleDriveConnection.create!(
      family: @user.family,
      user: @user,
      google_subject: "connection-google-subject",
      email: "connection@example.com",
      access_token: "expired-access-token",
      refresh_token: "long-lived-refresh-token",
      token_expires_at: 1.minute.ago,
      connected_at: Time.current
    )
  end

  test "refreshes an expired access token without discarding the refresh token" do
    GoogleDrive::Client.expects(:refresh_tokens).with(refresh_token: "long-lived-refresh-token").returns(
      "access_token" => "fresh-access-token",
      "expires_in" => 3600,
      "scope" => "openid email https://www.googleapis.com/auth/drive.file"
    )

    assert_equal "fresh-access-token", @connection.access_token!
    assert_equal "long-lived-refresh-token", @connection.reload.refresh_token
    assert @connection.token_expires_at.future?
  end

  test "marks the connection when refresh authorization is rejected" do
    GoogleDrive::Client.stubs(:refresh_tokens).raises(GoogleDrive::Client::AuthenticationError, "invalid_grant")

    assert_raises(GoogleDrive::Client::AuthenticationError) { @connection.access_token! }
    assert @connection.reload.requires_reauthorization?
  end
end
