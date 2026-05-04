# Plain Ruby Object representing one row in the unified scheduled-payments table.
# Combines a ScheduledPayment + a date + (optionally) a ScheduledPaymentEntry.
class ScheduledPaymentOccurrence
  attr_reader :scheduled_payment, :scheduled_date, :entry

  def initialize(scheduled_payment:, scheduled_date:, entry: nil)
    @scheduled_payment = scheduled_payment
    @scheduled_date = scheduled_date
    @entry = entry
  end

  def status
    return :scheduled if entry.nil?
    case entry.status
    when "pending" then :pending
    when "confirmed" then :confirmed
    when "skipped", "rejected" then :skipped
    end
  end

  def scheduled?  ; status == :scheduled  ; end
  def pending?    ; status == :pending    ; end
  def confirmed?  ; status == :confirmed  ; end
  def skipped?    ; status == :skipped    ; end

  def entry_id
    entry&.id
  end
end
