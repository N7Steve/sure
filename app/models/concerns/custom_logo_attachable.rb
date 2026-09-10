module CustomLogoAttachable
  extend ActiveSupport::Concern

  ALLOWED_CUSTOM_LOGO_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_CUSTOM_LOGO_SIZE = 5.megabytes

  included do
    has_one_attached :custom_logo, dependent: :purge_later do |attachable|
      attachable.variant :small,
                         resize_to_fill: [ 128, 128 ],
                         convert: :webp,
                         saver: { quality: 85 }
    end

    validate :custom_logo_has_supported_content_type
    validate :custom_logo_has_valid_size
  end

  def custom_logo_url
    return unless custom_logo.attached?
    return unless custom_logo.blob&.persisted?
    return unless custom_logo.content_type.in?(ALLOWED_CUSTOM_LOGO_CONTENT_TYPES)

    Rails.application.routes.url_helpers.rails_representation_path(
      custom_logo.variant(:small),
      only_path: true
    )
  end

  private
    def custom_logo_has_supported_content_type
      return unless custom_logo.attached?
      return if custom_logo.content_type.in?(ALLOWED_CUSTOM_LOGO_CONTENT_TYPES)

      errors.add(:custom_logo, I18n.t("shared.custom_logo_field.invalid_content_type"))
    end

    def custom_logo_has_valid_size
      return unless custom_logo.attached?
      return if custom_logo.byte_size <= MAX_CUSTOM_LOGO_SIZE

      errors.add(:custom_logo, I18n.t("shared.custom_logo_field.invalid_file_size", max_megabytes: 5))
    end
end
