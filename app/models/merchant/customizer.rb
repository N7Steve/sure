class Merchant::Customizer
  Result = Data.define(:merchant, :success, :converted) do
    def success?
      success
    end

    def converted?
      converted
    end
  end

  def initialize(family:, merchant:, attributes:, custom_logo: nil, delete_custom_logo: false)
    @family = family
    @merchant = merchant
    @attributes = attributes
    @custom_logo = custom_logo
    @delete_custom_logo = delete_custom_logo
  end

  def call
    result = if convert_provider_merchant?
      convert_provider_merchant
    elsif merchant.is_a?(ProviderMerchant)
      update_provider_merchant
    else
      update_family_merchant
    end

    family.reset_merchant_customizations_cache! if result.success?
    result
  rescue ActiveRecord::RecordInvalid => error
    Result.new(merchant: error.record, success: false, converted: convert_provider_merchant?)
  end

  private
    attr_reader :family, :merchant, :attributes, :custom_logo, :delete_custom_logo

    def update_family_merchant
      saved = false

      Merchant.transaction do
        raise ActiveRecord::Rollback unless merchant.update(attributes)
        raise ActiveRecord::Rollback unless persist_custom_logo_for(merchant)

        saved = true
      end

      Result.new(merchant: merchant, success: saved, converted: false)
    end

    def update_provider_merchant
      saved = false

      Merchant.transaction do
        if attributes.key?(:website_url)
          raise ActiveRecord::Rollback unless merchant.update(attributes.slice(:website_url))

          merchant.generate_logo_url_from_website!
        end

        raise ActiveRecord::Rollback unless persist_custom_logo_for(merchant)

        saved = true
      end

      Result.new(merchant: merchant, success: saved, converted: false)
    end

    def convert_provider_merchant
      converted = nil
      saved = false

      Merchant.transaction do
        converted = merchant.convert_to_family_merchant_for(family, attributes)
        raise ActiveRecord::Rollback unless persist_custom_logo_for(converted)

        saved = true
      end

      Result.new(merchant: converted, success: saved, converted: true)
    end

    def convert_provider_merchant?
      merchant.is_a?(ProviderMerchant) &&
        attributes[:name].present? &&
        attributes[:name] != merchant.name
    end

    def persist_custom_logo_for(target)
      customization = family.merchant_customizations.find_or_initialize_by(merchant: target)

      if custom_logo.present?
        customization.custom_logo = custom_logo
        return true if customization.save

        copy_customization_errors(customization, target)
        false
      elsif delete_custom_logo
        customization.destroy! if customization.persisted?
        true
      else
        true
      end
    end

    def copy_customization_errors(customization, target)
      customization.errors[:custom_logo].each do |message|
        target.errors.add(:custom_logo, message)
      end
    end
end
