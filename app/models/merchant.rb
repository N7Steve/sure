class Merchant < ApplicationRecord
  TYPES = %w[FamilyMerchant ProviderMerchant].freeze

  # Merchant name key for i18n
  NO_MERCHANT_NAME_KEY = "models.merchant.no_merchant"

  # Stable, non-localized filter value for the synthetic "No merchant" option.
  # Using an opaque sentinel (rather than the translated display name) means a real
  # merchant can never collide with it, regardless of name or locale.
  NO_MERCHANT_FILTER_VALUE = "__no_merchant__"

  has_many :transactions, dependent: :nullify
  has_many :scheduled_payments, dependent: :nullify
  has_many :recurring_transactions, dependent: :destroy
  has_many :merchant_customizations, dependent: :destroy

  validates :name, presence: true
  validates :name, exclusion: { in: [ NO_MERCHANT_FILTER_VALUE ] }
  validates :type, inclusion: { in: TYPES }

  scope :alphabetically, -> { order(:name) }

  class << self
    def no_merchant
      new(name: I18n.t(NO_MERCHANT_NAME_KEY))
    end

    def no_merchant_name
      I18n.t(NO_MERCHANT_NAME_KEY)
    end
  end

  def filter_value
    persisted? ? name : NO_MERCHANT_FILTER_VALUE
  end

  def display_logo_url(family:)
    customization = family&.merchant_customization_for(self)
    return customization.custom_logo_url if customization&.custom_logo&.attached?
    return if logo_url.blank?

    Setting.transform_brand_fetch_url(logo_url)
  end
end
