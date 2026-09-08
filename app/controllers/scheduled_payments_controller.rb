class ScheduledPaymentsController < ApplicationController
  layout -> { turbo_frame_request? ? false : "application" }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, Money::ConversionError, with: :invalid_payment_operation

  def index
    @view = ScheduledPayment::Agenda::VIEWS.include?(params[:view]) ? params[:view] : "overview"
    @agenda = ScheduledPayment::Agenda.new(family: Current.family, user: Current.user, month: params[:month])
    prepare_forecast if @view == "forecast"
  end

  def new
    if params[:from_entry_id].present?
      source_entry = Current.family.entries
        .joins(:account)
        .merge(Account.writable_by(Current.user))
        .where(entryable_type: "Transaction")
        .find(params[:from_entry_id])

      transaction = source_entry.entryable
      is_transfer = transaction.transfer.present?
      if is_transfer
        source_entry = transaction.transfer.outflow_transaction.entry
        [ source_entry.account, transaction.transfer.to_account ].each do |account|
          Current.family.accounts.writable_by(Current.user).find(account.id)
        end
        transaction = source_entry.entryable
      end

      @scheduled_payment = Current.family.scheduled_payments.build(
        title: source_entry.name,
        amount: source_entry.amount.abs,
        currency: source_entry.currency,
        account_id: source_entry.account_id,
        category_id: transaction.category_id,
        merchant_id: transaction.respond_to?(:merchant_id) ? transaction.merchant_id : nil,
        start_date: source_entry.date,
        frequency: "monthly",
        payment_type: is_transfer ? "transfer" : (source_entry.amount.positive? ? "expense" : "income"),
        target_account_id: is_transfer ? transaction.transfer.to_account&.id : nil
      )

      # Pre-select tags
      if transaction.respond_to?(:tags)
        @scheduled_payment.tag_ids = transaction.tag_ids
      end

      @from_entry_id = source_entry.id
    else
      @scheduled_payment = Current.family.scheduled_payments.build(
        currency: Current.family.primary_currency_code,
        start_date: Date.current,
        frequency: "monthly",
        payment_type: "expense"
      )
    end
  end

  def create
    @scheduled_payment = Current.family.scheduled_payments.build(scheduled_payment_params)
    @scheduled_payment.next_run_date ||= @scheduled_payment.start_date

    if @scheduled_payment.save
      # Link matching historical entries (best-effort, non-blocking)
      if params[:scheduled_payment][:from_entry_id].present?
        begin
          @scheduled_payment.link_matching_entries!(Current.user)
        rescue => e
          Rails.logger.error("Failed to link matching entries for SP #{@scheduled_payment.id}: #{e.class} - #{e.message}")
        end
      end

      flash[:notice] = t("scheduled_payments.created")
      target = agenda_return_path
      respond_to do |format|
        format.html { redirect_to target }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, target) }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render :new, formats: [ :html ], status: :unprocessable_entity }
      end
    end
  end

  def edit
    @scheduled_payment = find_scheduled_payment
  end

  def update
    @scheduled_payment = find_scheduled_payment
    attributes = scheduled_payment_params
    updated = @scheduled_payment.with_lock do
      # Association writers (tags) can write before model validation fails.
      raise ActiveRecord::Rollback unless @scheduled_payment.update(attributes)

      @scheduled_payment.sync_confirmed_entries!
      true
    end
    if updated
      flash[:notice] = t("scheduled_payments.updated")
      target = agenda_return_path
      respond_to do |format|
        format.html { redirect_to target }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, target) }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.turbo_stream { render :edit, formats: [ :html ], status: :unprocessable_entity }
      end
    end
  end

  def destroy
    sp = find_scheduled_payment
    sp.with_lock { sp.destroy! }
    flash[:notice] = t("scheduled_payments.deleted")
    redirect_to agenda_return_path
  end

  def toggle_status
    sp = find_scheduled_payment

    sp.with_lock do
      if sp.completed?
        flash[:alert] = t("scheduled_payments.cannot_toggle_completed", default: "Cannot reactivate a completed scheduled payment")
        redirect_to agenda_return_path
        return
      end

      sp.active? ? sp.update!(status: "paused") : sp.update!(status: "active")
    end
    flash[:notice] = sp.active? ? t("scheduled_payments.activated", default: "Scheduled payment activated") : t("scheduled_payments.paused", default: "Scheduled payment paused")
    redirect_to agenda_return_path
  end

  def confirm_entry_form
    @scheduled_payment = find_scheduled_payment
    @entry_to_confirm = params[:entry_id].present? ?
      @scheduled_payment.scheduled_payment_entries.where(status: %w[pending skipped rejected]).find(params[:entry_id]) :
      nil
    @scheduled_date = params[:scheduled_date].present? ? Date.iso8601(params[:scheduled_date].to_s) : @entry_to_confirm&.scheduled_date

    # Lógica de fecha preseleccionada
    @default_date = if @scheduled_date && @scheduled_date >= Date.current
                      Date.current
                    else
                      @scheduled_date || Date.current
                    end

    @default_amount = @scheduled_payment.amount.abs
    render layout: false
  end

  def confirm_entry
    entry = find_pending_entry
    custom_date = params[:confirm_date].present? ? Date.iso8601(params[:confirm_date].to_s) : nil
    custom_amount = params[:confirm_amount].present? ? BigDecimal(params[:confirm_amount].to_s) : nil
    entry.confirm!(date_override: custom_date, amount_override: custom_amount)
    flash[:notice] = t("scheduled_payments.entry_confirmed")
    redirect_to agenda_return_path
  end

  def reject_entry
    entry = find_pending_entry
    entry.reject!(params[:reason])
    flash[:notice] = t("scheduled_payments.entry_rejected")
    redirect_to agenda_return_path
  end

  def confirm_scheduled_date
    sp = find_scheduled_payment
    date = Date.iso8601(params[:scheduled_date].to_s)
    custom_date = params[:confirm_date].present? ? Date.iso8601(params[:confirm_date].to_s) : nil
    custom_amount = params[:confirm_amount].present? ? BigDecimal(params[:confirm_amount].to_s) : nil

    sp.confirm_on!(date, date_override: custom_date, amount_override: custom_amount)

    flash[:notice] = t("scheduled_payments.entry_confirmed")
    redirect_to agenda_return_path
  end

  def skip_scheduled_date
    sp = find_scheduled_payment
    date = Date.iso8601(params[:scheduled_date].to_s)

    sp.skip_on!(date)

    flash[:notice] = t("scheduled_payments.entry_skipped", default: "Entry skipped")
    redirect_to agenda_return_path
  end

  def retract_entry
    sp = find_scheduled_payment
    entry = sp.scheduled_payment_entries.confirmed.find(params[:entry_id])
    entry.retract!
    flash[:notice] = t("scheduled_payments.entry_retracted", default: "Confirmation undone, transaction removed")
    redirect_to agenda_return_path
  end

  def restore_entry
    sp = find_scheduled_payment
    entry = sp.scheduled_payment_entries.where(status: %w[skipped rejected]).find(params[:entry_id])

    past_due = entry.scheduled_date <= Date.current
    entry.restore!
    if past_due
      # Date has passed — auto-confirm (creates the transaction)
      flash[:notice] = t("scheduled_payments.entry_confirmed")
    else
      # Date hasn't arrived — destroy the SPE so it reverts to "Programado"
      # (in the unified table, "Programado" = no SPE exists for that date)
      flash[:notice] = t("scheduled_payments.entry_restored", default: "Entry restored")
    end

    redirect_to agenda_return_path
  end

  def run_now
    failures = GenerateScheduledPaymentsJob.perform_now(Current.family.id, Current.user.id)
    if failures.zero?
      flash[:notice] = t("scheduled_payments.job_ran", default: "Scheduled payments job executed successfully")
    else
      flash[:alert] = t("scheduled_payments.generation_failed", count: failures)
    end
    redirect_to agenda_return_path
  end

  private

  def prepare_forecast
    @forecast_accounts = Current.family.accounts.accessible_by(Current.user).visible
      .where(accountable_type: "Depository").alphabetically.to_a
    requested_account = @forecast_accounts.find do |account|
      account.id.to_s == params[:account_id].to_s
    end
    @forecast_account = requested_account || @forecast_accounts.first
    return unless @forecast_account

    @forecast = ScheduledPayment::Forecast.new(
      family: Current.family,
      user: Current.user,
      account: @forecast_account,
      horizon_months: params[:horizon]
    )
  end

  def agenda_return_path
    return scheduled_payments_path unless params[:agenda_view].present? || params[:agenda_month].present?

    view = ScheduledPayment::Agenda::VIEWS.include?(params[:agenda_view]) ? params[:agenda_view] : "overview"
    scheduled_payments_path(
      view: view,
      month: ScheduledPayment::Agenda.month_from(params[:agenda_month]).iso8601,
      account_id: (params[:agenda_account_id] if view == "forecast"),
      horizon: (params[:agenda_horizon] if view == "forecast")
    )
  end

  def find_scheduled_payment
    payment = Current.family.scheduled_payments.writable_by(Current.user).find(params[:id])
    payment.ensure_writable_by!(Current.user)
    payment
  end

  def find_pending_entry
    sp = find_scheduled_payment
    sp.scheduled_payment_entries.where(status: %w[pending skipped rejected]).find(params[:entry_id])
  end

  def scheduled_payment_params
    attributes = params.require(:scheduled_payment).permit(
      :title, :amount, :currency, :frequency,
      :start_date, :end_date, :account_id, :category_id,
      :merchant_id, :target_account_id, :payment_type, :auto_confirm, :amount_estimated,
      tag_ids: []
    )
    %i[account_id target_account_id].each do |key|
      Current.family.accounts.writable_by(Current.user).find(attributes[key]) if attributes[key].present?
    end
    Current.family.categories.find(attributes[:category_id]) if attributes[:category_id].present?
    Current.family.available_merchants_for(Current.user).find(attributes[:merchant_id]) if attributes[:merchant_id].present?
    Current.family.tags.find(attributes[:tag_ids].reject(&:blank?)) if attributes[:tag_ids].present?
    attributes
  end

  def invalid_payment_operation
    redirect_to agenda_return_path, alert: t("scheduled_payments.invalid_operation")
  end
end
