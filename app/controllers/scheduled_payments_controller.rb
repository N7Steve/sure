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
      .includes(scheduled_payment: [:account, :merchant, :category, :target_account])
      .order(scheduled_date: :asc)

    # Preload pending counts per scheduled payment for inline display
    @pending_counts = @pending_entries.reorder("").group(:scheduled_payment_id).count

    # Build a hash of scheduled_payment_id => oldest pending entry (for inline confirm/reject)
    @oldest_pending_per_sp = {}
    @pending_entries.each do |entry|
      sp_id = entry.scheduled_payment_id
      if @oldest_pending_per_sp[sp_id].nil? || entry.scheduled_date < @oldest_pending_per_sp[sp_id].scheduled_date
        @oldest_pending_per_sp[sp_id] = entry
      end
    end
  end

  def new
    if params[:from_entry_id].present?
      source_entry = Current.family.entries
        .joins(:account)
        .merge(Account.accessible_by(Current.user))
        .find(params[:from_entry_id])

      transaction = source_entry.entryable
      is_transfer = transaction.transfer.present?

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
      redirect_to transactions_path(tab: "scheduled")
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
      @scheduled_payment.sync_confirmed_entries!
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

  def confirm_scheduled_date
    sp = find_scheduled_payment
    date = Date.parse(params[:scheduled_date])

    ActiveRecord::Base.transaction do
      spe = sp.scheduled_payment_entries.find_or_initialize_by(scheduled_date: date)
      if spe.new_record?
        spe.status = "pending"
        spe.save!
      end
      spe.confirm! unless spe.confirmed?

      sp.advance_next_run_date! if sp.next_run_date == date
    end

    flash[:notice] = t("scheduled_payments.entry_confirmed")
    redirect_back_or_to transactions_path(tab: "scheduled")
  end

  def skip_scheduled_date
    sp = find_scheduled_payment
    date = Date.parse(params[:scheduled_date])

    ActiveRecord::Base.transaction do
      spe = sp.scheduled_payment_entries.find_or_initialize_by(scheduled_date: date)
      spe.assign_attributes(status: "skipped", rejection_reason: "skipped_by_user")
      spe.save!

      # If this skipped date matches the SP's next_run_date, advance it so the
      # cron doesn't try to generate this entry again.
      sp.advance_next_run_date! if sp.next_run_date == date
    end

    flash[:notice] = t("scheduled_payments.entry_skipped", default: "Entry skipped")
    redirect_back_or_to transactions_path(tab: "scheduled")
  end

  def retract_entry
    sp = find_scheduled_payment
    entry = sp.scheduled_payment_entries.confirmed.find(params[:entry_id])
    entry.retract!
    flash[:notice] = t("scheduled_payments.entry_retracted", default: "Confirmation undone, transaction removed")
    redirect_back_or_to transactions_path(tab: "scheduled")
  end

  def restore_entry
    sp = find_scheduled_payment
    entry = sp.scheduled_payment_entries.where(status: %w[skipped rejected]).find(params[:entry_id])

    if entry.scheduled_date <= Date.current
      # Date has passed — auto-confirm (creates the transaction)
      entry.confirm!
      flash[:notice] = t("scheduled_payments.entry_confirmed")
    else
      # Date hasn't arrived — destroy the SPE so it reverts to "Programado"
      # (in the unified table, "Programado" = no SPE exists for that date)
      entry.destroy!
      flash[:notice] = t("scheduled_payments.entry_restored", default: "Entry restored")
    end

    redirect_back_or_to transactions_path(tab: "scheduled")
  end

  def run_now
    GenerateScheduledPaymentsJob.perform_now
    flash[:notice] = t("scheduled_payments.job_ran", default: "Scheduled payments job executed successfully")
    redirect_to scheduled_payments_path
  end

  private

  def find_scheduled_payment
    Current.family.scheduled_payments.accessible_by(Current.user).find(params[:id])
  end

  def find_pending_entry
    sp = find_scheduled_payment
    sp.scheduled_payment_entries.where(status: %w[pending skipped rejected]).find(params[:entry_id])
  end

  def scheduled_payment_params
    params.require(:scheduled_payment).permit(
      :title, :amount, :currency, :frequency,
      :start_date, :end_date, :account_id, :category_id,
      :merchant_id, :target_account_id, :payment_type, :auto_confirm,
      tag_ids: []
    )
  end
end
