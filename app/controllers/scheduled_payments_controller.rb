class ScheduledPaymentsController < ApplicationController
  layout "settings"

  def index
    @scheduled_payments = Current.family.scheduled_payments
                                .accessible_by(Current.user)
                                .order(next_run_date: :asc)

    @pending_entries = ScheduledPaymentEntry
      .joins(:scheduled_payment)
      .where(scheduled_payments: { family_id: Current.family.id })
      .pending
      .where("scheduled_date <= ?", Date.current)
      .includes(scheduled_payment: [:account, :merchant, :category])
      .order(scheduled_date: :desc)
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
    sp.active? ? sp.update!(status: "paused") : sp.update!(status: "active")
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
    ScheduledPaymentEntry.joins(:scheduled_payment)
      .where(scheduled_payments: { family_id: Current.family.id })
      .pending
      .find(params[:entry_id])
  end

  def scheduled_payment_params
    params.require(:scheduled_payment).permit(
      :title, :amount, :currency, :frequency, :frequency_day,
      :start_date, :end_date, :account_id, :category_id,
      :merchant_id, :target_account_id, :payment_type, :auto_confirm
    )
  end
end
