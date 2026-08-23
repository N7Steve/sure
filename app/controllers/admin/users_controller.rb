# frozen_string_literal: true

module Admin
  class UsersController < Admin::BaseController
    before_action :set_user, only: %i[update deletion destroy]

    def index
      authorize User
      scope = policy_scope(User)
        .left_joins(family: :subscription)
        .includes(family: :subscription)

      scope = scope.where(role: params[:role]) if params[:role].present?
      scope = apply_trial_filter(scope) if params[:trial_status].present?

      users = scope.order(
        Arel.sql(
          "CASE " \
          "WHEN subscriptions.status = 'trialing' THEN 0 " \
          "WHEN subscriptions.id IS NULL THEN 1 " \
          "ELSE 2 END, " \
          "subscriptions.trial_ends_at ASC NULLS LAST, users.email ASC"
        )
      )

      family_ids = users.map(&:family_id).uniq
      @users_count_by_family = User.where(family_id: family_ids).group(:family_id).count
      @accounts_count_by_family = Account.where(family_id: family_ids).group(:family_id).count
      @entries_count_by_family = Entry.joins(:account).where(accounts: { family_id: family_ids }).group("accounts.family_id").count

      user_ids = users.map(&:id).uniq
      @last_login_by_user = Session.where(user_id: user_ids).group(:user_id).maximum(:created_at)
      @sessions_count_by_user = Session.where(user_id: user_ids).group(:user_id).count

      @families_with_users = users.group_by(&:family).sort_by do |family, _users|
        -(@entries_count_by_family[family.id] || 0)
      end

      @invitations_by_family = Invitation.pending
        .where(family_id: family_ids)
        .group_by(&:family_id)

      @demo_family_ids = ApiKey
        .joins(:user)
        .where(display_key: ApiKey::DEMO_MONITORING_KEY)
        .distinct
        .pluck("users.family_id")

      @trials_expiring_in_7_days = Subscription
        .where(status: :trialing)
        .where(trial_ends_at: Time.current..7.days.from_now)
        .count
      @sso_identity_blocks = SsoIdentityBlock.order(created_at: :desc)

      # Used by the view to hide the "remove" action for the sole remaining
      # active super admin, computed once here instead of per-row.
      @active_super_admin_count = User.where(role: :super_admin, active: true).count
    end

    def update
      authorize @user

      if @user.update(user_params)
        Rails.logger.info(
          "[Admin::Users] Role changed - " \
          "by_user_id=#{Current.user.id} " \
          "target_user_id=#{@user.id} " \
          "new_role=#{@user.role}"
        )
        redirect_to admin_users_path, notice: t(".success")
      else
        redirect_to admin_users_path, alert: t(".failure")
      end
    end

    def deletion
      # Same self-removal short-circuit as #destroy. UserPolicy#destroy? already
      # denies it, but Pundit::NotAuthorizedError is not rescued anywhere in this
      # app, so opening the confirmation modal for yourself (the index view hides
      # the button, but the URL is guessable) would 500 instead of redirecting.
      if @user.id == Current.user.id
        redirect_to admin_users_path, alert: t("admin.users.destroy.cannot_remove_self")
        return
      end

      authorize @user, :destroy?
      prepare_deletion_context
      render layout: false
    end

    def destroy
      # Self-removal is also denied by UserPolicy#destroy?, but checking it here
      # first turns it into a friendly redirect instead of an unhandled
      # Pundit::NotAuthorizedError (there is no rescue_from for it in this app).
      if @user.id == Current.user.id
        redirect_to admin_users_path, alert: t(".cannot_remove_self")
        return
      end

      authorize @user

      prepare_deletion_context
      confirmation_matches = ActiveSupport::SecurityUtils.secure_compare(
        params[:confirmation_text].to_s,
        @deletion_confirmation
      )
      unless confirmation_matches
        redirect_to admin_users_path, alert: t(".confirmation_mismatch")
        return
      end

      removed = @user.transaction do
        next false unless @user.permanently_remove!

        SsoAuditLog.log_user_removed!(user: @user, actor: Current.user, request: request)
        true
      end

      if removed
        redirect_to admin_users_path, notice: t(".success")
      else
        redirect_to admin_users_path, alert: @user.errors.full_messages.to_sentence.presence || t(".failure")
      end
    rescue ActiveRecord::RecordNotDestroyed => error
      DebugLogEntry.capture(
        category: "user_management",
        level: "error",
        message: "Permanent user removal failed while destroying an associated record",
        source: self.class.name,
        family: @user&.family,
        user: @user,
        metadata: {
          target_user_id: @user&.id,
          error_class: error.class.name,
          error_message: error.message,
          record_type: error.record&.class&.name,
          record_id: error.record&.id
        }
      )
      redirect_to admin_users_path, alert: t(".failure")
    end

    private

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:role)
      end

      def prepare_deletion_context
        family = @user.family
        @deletes_family = family.users.count == 1
        @family_accounts_count = family.accounts.count
        @family_transactions_count = family.entries.count
        @deletion_confirmation = if @deletes_family && family.name.present?
          family.name
        else
          @user.email
        end
      end

      def apply_trial_filter(scope)
        case params[:trial_status]
        when "expiring_soon"
          scope.where(subscriptions: { status: :trialing })
            .where(subscriptions: { trial_ends_at: Time.current..7.days.from_now })
        when "trialing"
          scope.where(subscriptions: { status: :trialing })
        else
          scope
        end
      end
  end
end
