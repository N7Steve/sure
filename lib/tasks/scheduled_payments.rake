namespace :scheduled_payments do
  desc "Manually run the scheduled payments generation job (generates pending entries for payments due up to today)"
  task generate: :environment do
    puts "Running GenerateScheduledPaymentsJob..."
    GenerateScheduledPaymentsJob.perform_now
    puts "Done. Check scheduled_payment_entries for new pending entries."
  end

  desc "Generate scheduled payments as if today were a specific date (for testing)"
  task :generate_as, [:date] => :environment do |_t, args|
    target_date = Date.parse(args[:date])
    puts "Running scheduled payments generation as if today were #{target_date}..."

    ScheduledPayment.active.where("next_run_date <= ?", target_date).find_each do |sp|
      while sp.reload.next_run_date <= target_date && sp.active?
        entry = sp.generate_pending_entry!
        puts "  Generated entry for '#{sp.title}' on #{entry.scheduled_date} (status: #{entry.status})"
      end
    rescue => e
      puts "  ERROR for '#{sp.title}': #{e.message}"
    end

    puts "Done."
  end
end
