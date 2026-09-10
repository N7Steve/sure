class Merchant < ApplicationRecord
  TYPES = %w[FamilyMerchant ProviderMerchant].freeze

  has_many :transactions, dependent: :nullify
  has_many :scheduled_payments, dependent: :nullify
  has_many :recurring_transactions, dependent: :destroy
  has_many :merchant_customizations, dependent: :destroy

  validates :name, presence: true
  validates :type, inclusion: { in: TYPES }

  scope :alphabetically, -> { order(:name) }

  def display_logo_url(family:)
    customization = family&.merchant_customization_for(self)
    return customization.custom_logo_url if customization&.custom_logo&.attached?
    return if logo_url.blank?

    Setting.transform_brand_fetch_url(logo_url)
  end
end
