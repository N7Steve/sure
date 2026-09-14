module SettingsHelper
  def settings_nav_sections
    sections = [
      {
        header: t("settings.settings_nav.personal_family_section_title"),
        items: [
          settings_nav_item(:profile_label, :settings_profile_path, "circle-user"),
          settings_nav_item(:preferences_label, :settings_preferences_path, "bolt"),
          settings_nav_item(:appearance_label, :settings_appearance_path, "palette"),
          settings_nav_item(:security_label, :settings_security_path, "shield-check"),
          settings_nav_item(:payment_label, :settings_payment_path, "circle-dollar-sign", visible: !self_hosted? && Current.family&.can_manage_subscription?)
        ]
      },
      {
        header: t("settings.settings_nav.accounts_data_section_title"),
        items: [
          settings_nav_item(:accounts_label, :accounts_path, "layers"),
          settings_nav_item(:bank_sync_label, :settings_providers_path, "banknote", visible: admin_user?),
          settings_nav_item(:imports_label, :imports_path, "download", visible: admin_user?),
          settings_nav_item(:statement_vault_label, :account_statements_path, "archive", visible: admin_user?),
          settings_nav_item(:exports_label, :family_exports_path, "upload")
        ]
      },
      {
        header: t("settings.settings_nav.organization_section_title"),
        items: [
          settings_nav_item(:categories_label, :categories_path, "shapes"),
          settings_nav_item(:merchants_label, :family_merchants_path, "store"),
          settings_nav_item(:tags_label, :tags_path, "tags"),
          settings_nav_item(:rules_label, :rules_path, "git-branch")
        ]
      },
      {
        header: t("settings.settings_nav.integrations_section_title"),
        items: [
          settings_nav_item(:api_keys_label, :settings_api_keys_path, "key", visible: admin_user?),
          settings_nav_item(:mcp_label, :settings_mcp_path, "plug", visible: ai_admin_user?),
          settings_nav_item(:ai_prompts_label, :settings_ai_prompts_path, "bot", visible: ai_admin_user?),
          settings_nav_item(:llm_usage_label, :settings_llm_usage_path, "activity", visible: ai_admin_user?)
        ]
      },
      {
        header: t("settings.settings_nav.system_section_title"),
        items: [
          settings_nav_item(:users_label, :admin_users_path, "users", visible: super_admin_user?),
          settings_nav_item(:sso_providers_label, :admin_sso_providers_path, "key-round", visible: super_admin_user?),
          settings_nav_item(:self_hosting_label, :settings_hosting_path, "database", visible: self_hosted_and_admin?),
          settings_nav_item(:system_health_label, :admin_system_health_path, "heart-pulse", visible: super_admin_user?),
          settings_nav_item(:background_jobs_label, :settings_background_jobs_path, "list-checks", visible: super_admin_user?),
          settings_nav_item(:debug_label, :settings_debug_path, "bug", visible: super_admin_user?)
        ]
      },
      {
        header: t("settings.settings_nav.help_section_title"),
        items: [
          settings_nav_item(:guides_label, :settings_guides_path, "book-open"),
          settings_nav_item(:whats_new_label, :changelog_path, "box"),
          settings_nav_item(:feedback_label, :feedback_path, "megaphone")
        ]
      }
    ]

    sections.filter_map do |section|
      visible_items = section[:items].select { |item| item[:visible] }
      section.merge(items: visible_items) if visible_items.any?
    end
  end

  def adjacent_setting(current_path, offset)
    visible_settings = settings_nav_sections.flat_map { |section| section[:items] }
    current_index = visible_settings.index { |setting| setting[:path] == current_path }
    return nil unless current_index

    adjacent_index = current_index + offset
    return nil if adjacent_index < 0 || adjacent_index >= visible_settings.size

    adjacent = visible_settings[adjacent_index]

    render partial: "settings/settings_nav_link_large", locals: {
      path: adjacent[:path],
      direction: offset > 0 ? "next" : "previous",
      title: adjacent[:label]
    }
  end

  def settings_section(title: nil, subtitle: nil, collapsible: false, open: true, auto_open_param: nil, status: nil, meta: nil, actions: nil, badge: nil, &block)
    content = capture(&block)
    render partial: "settings/section", locals: { title: title, subtitle: subtitle, content: content, collapsible: collapsible, open: open, auto_open_param: auto_open_param, status: status, meta: meta, actions: actions, badge: badge }
  end

  def provider_summary(provider_key)
    key = provider_key.to_s.downcase

    case key
    when "plaid", "plaid_eu"
      configured = @provider_configurations&.find { |c| c.provider_key.to_s.casecmp(key).zero? }&.configured?
      configured ? { status: :ok } : { status: :off }
    when "akahu"
      return { status: :off } unless @akahu_items&.any?
      sync_based_summary(key)
    when "up"
      return { status: :off } unless @up_items&.any?
      sync_based_summary(key)
    when "simplefin"
      return { status: :off } unless @simplefin_items&.any?
      sync_based_summary(key)
    when "lunchflow"
      return { status: :off } unless @lunchflow_items&.any?
      sync_based_summary(key)
    when "enable_banking"
      return { status: :off } unless @enable_banking_items&.any?
      enable_banking_summary
    when "coinstats"
      return { status: :off } unless @coinstats_items&.any?
      sync_based_summary(key)
    when "mercury"
      return { status: :off } unless @mercury_items&.any?
      sync_based_summary(key)
    when "redbark"
      return { status: :off } unless @redbark_items&.any?
      sync_based_summary(key)
    when "brex"
      return { status: :off } unless @brex_items&.any?
      sync_based_summary(key)
    when "coinbase"
      return { status: :off } unless @coinbase_items&.any?
      sync_based_summary(key)
    when "binance"
      return { status: :off } unless @binance_items&.any?
      sync_based_summary(key)
    when "kraken"
      return { status: :off } unless @kraken_items&.any?
      sync_based_summary(key)
    when "onchain_wallet"
      return { status: :off } unless @onchain_wallet_items&.any?
      sync_based_summary(key)
    when "snaptrade"
      configured_item = @snaptrade_items&.find(&:oauth_configured?)
      return { status: :off } unless configured_item

      sync_based_summary(key)
    when "ibkr"
      return { status: :off } unless @ibkr_items&.any?
      sync_based_summary(key)
    when "trade_republic"
      return { status: :off } unless @trade_republic_items&.any?
      sync_based_summary(key)
    when "indexa_capital"
      return { status: :off } unless @indexa_capital_items&.any?
      sync_based_summary(key)
    when "sophtron"
      return { status: :off } unless @sophtron_items&.any?
      sync_based_summary(key)
    when "questrade"
      return { status: :off } unless @questrade_items&.any?
      sync_based_summary(key)
    else
      { status: :off }
    end
  end

  def settings_nav_footer
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "hidden md:flex flex-row justify-between gap-4" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  def settings_nav_footer_mobile
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "md:hidden flex flex-col gap-4 pb-[env(safe-area-inset-bottom)]" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  def yahoo_finance_health_presentation(status)
    status = status.to_sym if status.respond_to?(:to_sym)
    status = :unknown unless %i[healthy rate_limited unavailable unknown].include?(status)

    presentation = {
      status_class: {
        healthy: "bg-success",
        rate_limited: "bg-warning",
        unavailable: "bg-destructive",
        unknown: "bg-surface-inset"
      }.fetch(status),
      status_text: t("settings.hostings.yahoo_finance_settings.status_#{status}")
    }

    presentation[:alert] = case status
    when :rate_limited
      {
        title: t("settings.hostings.yahoo_finance_settings.rate_limited_title"),
        message: t("settings.hostings.yahoo_finance_settings.rate_limited_message"),
        variant: :warning
      }
    when :unavailable
      {
        title: t("settings.hostings.yahoo_finance_settings.unavailable_title"),
        message: t("settings.hostings.yahoo_finance_settings.unavailable_message"),
        variant: :warning
      }
    end

    presentation
  end

  # Below this many synced accounts, the per-row pills already give the user
  # enough at-a-glance signal and the strip is redundant chrome.
  HEALTH_STRIP_MIN_ACCOUNTS = 10

  # Slim health-strip data for the providers index. Pulls counts from the
  # already-resolved entry summaries plus the family's distinct synced-account
  # count for the trailing stat. Returns a hash consumed by the
  # `settings/providers/_health_strip` partial, or nil when the family has
  # fewer than HEALTH_STRIP_MIN_ACCOUNTS connected accounts.
  def provider_health_strip(connected:, needs_attention:)
    accounts_count = Current.family.accounts.joins(:account_providers).distinct.count
    return nil if accounts_count < HEALTH_STRIP_MIN_ACCOUNTS

    active_entries = connected + needs_attention
    last_synced_at = active_entries.map { |e| e[:summary][:last_synced_at] }.compact.max

    {
      connected:        active_entries.size,
      needs_attention:  needs_attention.size,
      accounts_syncing: accounts_count,
      last_synced_at:   last_synced_at
    }
  end

  # Strips the leading "about " from `time_ago_in_words` so copy reads as
  # "Synced 6 hours ago" instead of "Synced about 6 hours ago".
  def concise_time_ago(time)
    time_ago_in_words(time).sub(/\Aabout /, "")
  end

  private
    def sync_based_summary(provider_key)
      health = @provider_sync_health&.dig(provider_key) || {}
      last_synced_at = health[:last_synced_at]

      base = if health[:error]
        { status: :err, meta: t("settings.providers.meta.sync_error") }
      elsif health[:stale]
        { status: :warn, meta: t("settings.providers.meta.no_recent_sync") }
      elsif last_synced_at.present?
        { status: :ok, meta: t("settings.providers.meta.last_synced", time: concise_time_ago(last_synced_at)) }
      else
        { status: :ok }
      end

      base.merge(last_synced_at: last_synced_at)
    end

    def enable_banking_summary
      health = @provider_sync_health&.dig("enable_banking") || {}
      last_synced_at = health[:last_synced_at]

      return { status: :err, meta: t("settings.providers.meta.sync_error"), last_synced_at: nil } if health[:error]

      valid_items = @enable_banking_items&.select(&:session_valid?) || []

      # All items have expired/missing sessions — need re-authorization
      if valid_items.empty?
        return { status: :warn, meta: t("settings.providers.meta.reconsent_required"), last_synced_at: last_synced_at }
      end

      expiring = valid_items.find do |item|
        item.session_expires_at.present? && item.session_expires_at < 7.days.from_now
      end

      if expiring
        days = [ ((expiring.session_expires_at - Time.current) / 1.day).ceil, 1 ].max
        return { status: :warn, meta: t("settings.providers.meta.reconsent_needed", count: days), last_synced_at: last_synced_at }
      end

      return { status: :warn, meta: t("settings.providers.meta.no_recent_sync"), last_synced_at: last_synced_at } if health[:stale]

      if last_synced_at.present?
        { status: :ok, meta: t("settings.providers.meta.last_synced", time: concise_time_ago(last_synced_at)), last_synced_at: last_synced_at }
      else
        { status: :ok, last_synced_at: nil }
      end
    end

    def settings_nav_item(label_key, path_helper, icon_name, visible: true)
      {
        label: t("settings.settings_nav.#{label_key}"),
        path: public_send(path_helper),
        icon: icon_name,
        visible: visible
      }
    end

    # Visibility helpers shared by the sidebar and adjacent navigation.
    def admin_user?
      Current.user&.admin?
    end

    def super_admin_user?
      Current.user&.super_admin?
    end

    def ai_admin_user?
      ai_features_enabled? && admin_user?
    end

    def self_hosted_and_admin?
      self_hosted? && admin_user?
    end
end
