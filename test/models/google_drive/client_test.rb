require "test_helper"

class GoogleDrive::ClientTest < ActiveSupport::TestCase
  test "authorization URL requests offline per-file access with PKCE" do
    GoogleDrive::Client.stubs(:client_id).returns("client-id")
    GoogleDrive::Client.stubs(:client_secret).returns("client-secret")

    url = GoogleDrive::Client.authorization_url(
      redirect_uri: "https://sure.example/google_drive_connection/callback",
      state: "secure-state",
      code_challenge: "challenge"
    )
    params = Rack::Utils.parse_query(URI(url).query)

    assert_equal "offline", params["access_type"]
    assert_equal "secure-state", params["state"]
    assert_equal "challenge", params["code_challenge"]
    assert_includes params["scope"].split, "https://www.googleapis.com/auth/drive.file"
  end

  test "PKCE verifier and challenge are URL safe" do
    pkce = GoogleDrive::Client.generate_pkce

    assert_match(/\A[A-Za-z0-9_-]+\z/, pkce[:verifier])
    assert_match(/\A[A-Za-z0-9_-]+\z/, pkce[:challenge])
  end
end
