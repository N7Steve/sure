class MerchantCustomization < ApplicationRecord
  include CustomLogoAttachable

  belongs_to :family
  belongs_to :merchant

  validates :merchant_id, uniqueness: { scope: :family_id }
  validate :family_merchant_belongs_to_family

  private
    def family_merchant_belongs_to_family
      return unless merchant.is_a?(FamilyMerchant)
      return if merchant.family_id == family_id

      errors.add(:merchant, :invalid)
    end
end
