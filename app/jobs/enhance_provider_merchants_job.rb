class EnhanceProviderMerchantsJob < ApplicationJob
  queue_as :medium_priority

  def perform(family)
    return unless Setting.ai_features_enabled?

    ProviderMerchant::Enhancer.new(family).enhance
  ensure
    Rails.cache.delete("enhance_provider_merchants:#{family.id}")
  end
end
