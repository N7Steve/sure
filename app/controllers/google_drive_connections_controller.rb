class GoogleDriveConnectionsController < ApplicationController
  OAUTH_SESSION_TTL = 10.minutes

  def connect
    unless GoogleDrive::Client.configured?
      redirect_to family_exports_path, alert: t("google_drive_connections.not_configured")
      return
    end

    pkce = GoogleDrive::Client.generate_pkce
    state = SecureRandom.hex(32)
    session[:google_drive_oauth] = {
      "state" => state,
      "code_verifier" => pkce[:verifier],
      "user_id" => Current.user.id,
      "started_at" => Time.current.to_i
    }

    redirect_to GoogleDrive::Client.authorization_url(
      redirect_uri: callback_google_drive_connection_url,
      state: state,
      code_challenge: pkce[:challenge]
    ), allow_other_host: true
  end

  def callback
    oauth_session = (session.delete(:google_drive_oauth) || {}).with_indifferent_access
    unless valid_oauth_session?(oauth_session)
      redirect_to family_exports_path, alert: t("google_drive_connections.state_mismatch")
      return
    end

    if params[:error].present?
      redirect_to family_exports_path, alert: t("google_drive_connections.access_denied")
      return
    end

    if params[:code].blank?
      redirect_to family_exports_path, alert: t("google_drive_connections.connection_failed")
      return
    end

    payload = GoogleDrive::Client.exchange_code(
      code: params[:code],
      redirect_uri: callback_google_drive_connection_url,
      code_verifier: oauth_session[:code_verifier]
    )
    verify_required_scope!(payload)
    profile = GoogleDrive::Client.user_info(access_token: payload.fetch("access_token"))

    connection = Current.user.google_drive_connection || Current.user.build_google_drive_connection(family: Current.family)
    refresh_token = payload["refresh_token"].presence || connection.refresh_token
    raise GoogleDrive::Client::AuthenticationError, "Google did not return a refresh token" if refresh_token.blank?

    connection.assign_attributes(
      family: Current.family,
      google_subject: profile.fetch("sub"),
      email: profile.fetch("email"),
      access_token: payload.fetch("access_token"),
      refresh_token: refresh_token,
      token_expires_at: payload["expires_in"].present? ? payload["expires_in"].to_i.seconds.from_now : nil,
      scopes: payload["scope"].to_s,
      status: :connected,
      connected_at: Time.current
    )
    connection.save!
    connection.export_schedules.where(last_error_code: "reauthorization_required").update_all(
      status: "active",
      last_error_code: nil,
      updated_at: Time.current
    )

    redirect_to family_exports_path, notice: t("google_drive_connections.connected", email: connection.email)
  rescue GoogleDrive::Client::Error, KeyError, ActiveRecord::RecordInvalid => e
    capture_oauth_failure(e)
    redirect_to family_exports_path, alert: t("google_drive_connections.connection_failed")
  end

  def destroy
    connection = Current.user.google_drive_connection
    if connection
      begin
        GoogleDrive::Client.revoke(token: connection.refresh_token)
      rescue GoogleDrive::Client::Error => e
        capture_oauth_failure(e)
      end
      connection.destroy!
    end

    redirect_to family_exports_path, notice: t("google_drive_connections.disconnected")
  end

  private
    def valid_oauth_session?(oauth_session)
      return false if params[:state].blank? || oauth_session[:state].blank?
      return false unless oauth_session[:user_id].to_s == Current.user.id.to_s
      return false if oauth_session[:started_at].to_i < OAUTH_SESSION_TTL.ago.to_i

      ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, oauth_session[:state].to_s)
    end

    def verify_required_scope!(payload)
      granted = payload["scope"].to_s.split
      return if granted.include?("https://www.googleapis.com/auth/drive.file")

      raise GoogleDrive::Client::PermissionError, "The Drive file permission was not granted"
    end

    def capture_oauth_failure(error)
      DebugLogEntry.capture(
        category: "provider_auth",
        level: "error",
        message: "Google Drive OAuth failed: #{error.class}",
        source: self.class.name,
        provider_key: "google_drive",
        family: Current.family,
        user: Current.user
      )
    end
end
