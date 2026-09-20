class GoogleDriveConnection < ApplicationRecord
  include Encryptable

  TOKEN_EXPIRY_LEEWAY = 2.minutes

  belongs_to :family
  belongs_to :user

  has_many :export_schedules,
           class_name: "GoogleDriveExportSchedule",
           dependent: :destroy,
           inverse_of: :google_drive_connection

  encrypts :access_token if encryption_ready?
  encrypts :refresh_token if encryption_ready?
  encrypts :google_subject, deterministic: true if encryption_ready?
  encrypts :email if encryption_ready?

  enum :status, {
    connected: "connected",
    requires_reauthorization: "requires_reauthorization"
  }, default: :connected, validate: true

  validates :google_subject, :email, :refresh_token, :connected_at, presence: true
  validates :user_id, uniqueness: true
  validate :user_belongs_to_family

  def apply_token_payload!(payload)
    refresh = payload["refresh_token"].presence || refresh_token
    raise GoogleDrive::Client::AuthenticationError, "Google did not return a refresh token" if refresh.blank?

    update!(
      access_token: payload.fetch("access_token"),
      refresh_token: refresh,
      token_expires_at: payload["expires_in"].present? ? payload["expires_in"].to_i.seconds.from_now : nil,
      scopes: payload["scope"].presence || scopes,
      status: :connected,
      connected_at: Time.current
    )
  end

  def access_token!(force_refresh: false)
    if !force_refresh && access_token.present? && token_expires_at.present? && token_expires_at > TOKEN_EXPIRY_LEEWAY.from_now
      return access_token
    end

    with_lock do
      reload
      if !force_refresh && access_token.present? && token_expires_at.present? && token_expires_at > TOKEN_EXPIRY_LEEWAY.from_now
        next access_token
      end

      payload = GoogleDrive::Client.refresh_tokens(refresh_token: refresh_token)
      apply_token_payload!(payload)
      access_token
    end
  rescue GoogleDrive::Client::AuthenticationError
    update_column(:status, "requires_reauthorization") if persisted?
    raise
  end

  private
    def user_belongs_to_family
      errors.add(:user, :invalid) if user.present? && family_id.present? && user.family_id != family_id
    end
end
