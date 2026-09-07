class GenerateScheduledPaymentsJob < ApplicationJob
  queue_as :scheduled

  def perform(family_id = nil, user_id = nil)
    today = Date.current
    payments = ScheduledPayment.due_on_or_before(today)
    payments = payments.where(family_id: family_id) if family_id
    payments = payments.writable_by(User.find(user_id)) if user_id
    failures = 0

    payments.find_each do |scheduled_payment|
      begin
        while scheduled_payment.generate_pending_entry!(through: today)
          # The locked generator checks the cutoff, including after another
          # worker has advanced the same schedule.
        end
      rescue => e
        failures += 1
        Rails.logger.error("Failed to generate entry for ScheduledPayment #{scheduled_payment.id}: #{e.class} - #{e.message}")
      end
    end

    failures
  end
end
