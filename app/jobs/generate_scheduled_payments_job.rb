class GenerateScheduledPaymentsJob < ApplicationJob
  queue_as :scheduled

  def perform
    today = Date.current

    ScheduledPayment.due_on_or_before(today).find_each do |scheduled_payment|
      begin
        while scheduled_payment.reload.next_run_date <= today && scheduled_payment.active?
          scheduled_payment.generate_pending_entry!
        end
      rescue => e
        Rails.logger.error("Failed to generate entry for ScheduledPayment #{scheduled_payment.id}: #{e.class} - #{e.message}")
      end
    end
  end
end
