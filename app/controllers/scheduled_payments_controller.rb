class ScheduledPaymentsController < ApplicationController
  layout "settings"

  def index
    @scheduled_payments = Current.family.scheduled_payments
                                .accessible_by(Current.user)
                                .includes(:account, :merchant, :category, :target_account)
                                .order(next_run_date: :asc)

    @pending_entries = ScheduledPaymentEntry
      .joins(:scheduled_payment)
      .where(scheduled_payment_id: Current.family.scheduled_payments.accessible_by(Current.user).select(:id))
      .pending
      .where("scheduled_date <= ?", Date.current)
      .includes(scheduled_payment: [:account, :merchant, :category, :target_account])
      .order(scheduled_date: :desc)

    # Preload pending counts per scheduled payment for inline display
    @pending_counts = @pending_entries.group(:scheduled_payment_id).count
  end

  def new
    @scheduled_payment = Current.family.scheduled_payments.build(
      currency: Current.family.primary_currency_code,
      start_date: Date.current,
      frequency: "monthly",
      payment_type: "expense"
    )
  end

  def create
    @scheduled_payment = Current.family.scheduled_payments.build(scheduled_payment_params)
    @scheduled_payment.next_run_date = @scheduled_payment.start_date

    if @scheduled_payment.save
      flash[:notice] = t("scheduled_payments.created")
      redirect_to scheduled_payments_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @scheduled_payment = find_scheduled_payment
  end

  def update
    @scheduled_payment = find_scheduled_payment
    if @scheduled_payment.update(scheduled_payment_params)
      flash[:notice] = t("scheduled_payments.updated")
      redirect_to scheduled_payments_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    find_scheduled_payment.destroy!
    flash[:notice] = t("scheduled_payments.deleted")
    redirect_to scheduled_payments_path
  end

  def toggle_status
    sp = find_scheduled_payment

    if sp.completed?
      flash[:alert] = t("scheduled_payments.cannot_toggle_completed", default: "Cannot reactivate a completed scheduled payment")
      redirect_to scheduled_payments_path
      return
    end

    sp.active? ? sp.update!(status: "paused") : sp.update!(status: "active")
    flash[:notice] = sp.active? ? t("scheduled_payments.activated", default: "Scheduled payment activated") : t("scheduled_payments.paused", default: "Scheduled payment paused")
    redirect_to scheduled_payments_path
  end

  def confirm_entry
    entry = find_pending_entry
    entry.confirm!
    flash[:notice] = t("scheduled_payments.entry_confirmed")
    redirect_back_or_to scheduled_payments_path
  end

  def reject_entry
    entry = find_pending_entry
    entry.reject!(params[:reason])
    flash[:notice] = t("scheduled_payments.entry_rejected")
    redirect_back_or_to scheduled_payments_path
  end

  private

  def find_scheduled_payment
    Current.family.scheduled_payments.accessible_by(Current.user).find(params[:id])
  end

  def find_pending_entry
    sp = find_scheduled_payment
    sp.scheduled_payment_entries.pending.find(params[:entry_id])
  end

  def scheduled_payment_params
    params.require(:scheduled_payment).permit(
      :title, :amount, :currency, :frequency,
      :start_date, :end_date, :account_id, :category_id,
      :merchant_id, :target_account_id, :payment_type, :auto_confirm
    )
  end
end
