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
      { key: "active", icon: "calendar-clock", values: [ @agenda.active_count ],
        hint: t("scheduled_payments.agenda.active_hint", count: @agenda.payments.size) },
      { key: "remaining", icon: "receipt", values: @agenda.remaining_expenses.map { |money| format_money(money) },
        hint: t("scheduled_payments.agenda.remaining_hint") },
      { key: "pending", icon: "list-checks", values: [ @agenda.pending_count ],
        hint: t("scheduled_payments.agenda.pending_hint") }
    ]
  end

  def agenda_planning_metrics
    [
      { key: "monthly_cost", values: @agenda.recurring_monthly_expenses.map { |money| format_money(money) },
        hint: t("scheduled_payments.agenda.monthly_cost_hint") },
      { key: "annual_cost", values: @agenda.recurring_annual_expenses.map { |money| format_money(money) },
        hint: t("scheduled_payments.agenda.annual_cost_hint") }
    ]
  end

  def agenda_display_amount(occurrence)
    amount = format_money(occurrence.display_amount_money)
    occurrence.amount_estimated? ? "≈#{amount}" : amount
  end

  def scheduled_payment_display_amount(payment, money = nil)
    money ||= Money.new(payment.income? ? payment.amount.abs : -payment.amount.abs, payment.currency)
    amount = format_money(money)
    payment.amount_estimated? ? "≈#{amount}" : amount
  end

  def scheduled_payment_category_name(payment_or_row)
    payment_or_row.category&.name || t("scheduled_payments.agenda.uncategorized")
  end

  def agenda_planning_row_amount(row, attribute)
    amount = format_money(Money.new(row.public_send(attribute), row.currency))
    row.amount_estimated ? "≈#{amount}" : amount
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
      "bg-info/10 text-info"
    end
  end

end
