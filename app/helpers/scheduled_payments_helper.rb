module ScheduledPaymentsHelper
  def agenda_context_params
    {
      agenda_view: @view || (ScheduledPayment::Agenda::VIEWS.include?(params[:agenda_view]) ? params[:agenda_view] : "overview"),
      agenda_month: (@agenda&.month || ScheduledPayment::Agenda.month_from(params[:agenda_month])).iso8601
    }
  end

  def agenda_back_path
    context = agenda_context_params
    scheduled_payments_path(view: context[:agenda_view], month: context[:agenda_month])
  end

  def agenda_metrics
    [
      { key: "active", values: [ @agenda.active_count ], hint: t("scheduled_payments.agenda.active_hint", count: @agenda.payments.size) },
      { key: "remaining", values: @agenda.remaining_expenses.map { |money| format_money(money) }, hint: t("scheduled_payments.agenda.remaining_hint") },
      { key: "pending", values: [ @agenda.pending_count ], hint: t("scheduled_payments.agenda.pending_hint") }
    ]
  end

  def agenda_status(occurrence)
    occurrence.overdue? ? :overdue : occurrence.status
  end

  def agenda_status_tone(status)
    { confirmed: :success, active: :success, pending: :warning, paused: :warning,
      scheduled: :info, overdue: :destructive }.fetch(status.to_sym, :neutral)
  end

  def agenda_occurrence_id(occurrence)
    dom_id(occurrence.scheduled_payment, "occurrence_#{occurrence.scheduled_date.iso8601}")
  end

  def agenda_confirm_path(occurrence)
    confirm_entry_form_scheduled_payment_path(occurrence.scheduled_payment,
      **agenda_context_params, entry_id: occurrence.entry_id, scheduled_date: occurrence.scheduled_date.iso8601)
  end

  def agenda_calendar_link(occurrence)
    if occurrence.open? && @agenda.writable?(occurrence.scheduled_payment)
      { href: agenda_confirm_path(occurrence), frame: :modal }
    else
      { href: scheduled_payments_path(month: occurrence.scheduled_date.beginning_of_month.iso8601,
          anchor: agenda_occurrence_id(occurrence)), frame: :_top }
    end
  end

  def agenda_calendar_classes(occurrence)
    if occurrence.confirmed?
      "bg-success/10 text-success"
    elsif occurrence.skipped?
      "bg-surface-inset text-secondary line-through"
    elsif occurrence.overdue?
      "bg-destructive/10 text-destructive"
    else
      "bg-surface-inset text-primary"
    end
  end

  def agenda_payment_icon(payment)
    return "arrow-right-left" if payment.transfer?

    payment.income? ? "arrow-down-left" : "arrow-up-right"
  end
end
