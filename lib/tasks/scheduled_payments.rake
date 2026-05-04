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

  desc "Show status of all scheduled payments and their entries"
  task status: :environment do
    ScheduledPayment.includes(:scheduled_payment_entries, :account, :merchant).find_each do |sp|
      merchant_name = sp.merchant&.name || "—"
      puts "\n#{sp.title} (#{sp.frequency}, #{sp.status})"
      puts "  Account: #{sp.account.name} | Merchant: #{merchant_name}"
      puts "  Amount: #{sp.amount} #{sp.currency} | Type: #{sp.payment_type}"
      puts "  Start: #{sp.start_date} | Next run: #{sp.next_run_date}"
      puts "  Entries (#{sp.scheduled_payment_entries.count}):"

      if sp.scheduled_payment_entries.any?
        sp.scheduled_payment_entries.order(scheduled_date: :asc).each do |entry|
          real_entry = entry.entry ? "→ Entry ##{entry.entry_id}" : "no real entry"
          puts "    #{entry.scheduled_date} | #{entry.status.upcase.ljust(10)} | #{real_entry}"
        end
      else
        puts "    (none)"
      end
    end
  end

  desc "Revert generate_as: delete pending entries with future scheduled_date and reset next_run_date"
  task revert_future: :environment do
    today = Date.current
    reverted = 0

    ScheduledPaymentEntry.pending.where("scheduled_date > ?", today).find_each do |entry|
      sp = entry.scheduled_payment
      entry_date = entry.scheduled_date
      puts "Reverting '#{sp.title}' entry for #{entry_date}..."

      entry.destroy!
      sp.update_columns(next_run_date: entry_date)

      puts "  Deleted entry, reset next_run_date to #{entry_date}"
      reverted += 1
    end

    if reverted == 0
      puts "No future pending entries found. Nothing to revert."
    else
      puts "\nReverted #{reverted} entries."
    end
  end

  desc "Delete ALL pending entries (nuclear reset for testing)"
  task purge_pending: :environment do
    count = ScheduledPaymentEntry.pending.count
    if count == 0
      puts "No pending entries found."
    else
      print "About to delete #{count} pending entries. Are you sure? (y/N): "
      confirm = $stdin.gets.chomp.downcase
      if confirm == "y"
        ScheduledPaymentEntry.pending.destroy_all
        puts "Deleted #{count} pending entries."
        puts "Note: next_run_date of parent ScheduledPayments was NOT reset."
        puts "You may need to edit them manually or run 'revert_future' instead."
      else
        puts "Cancelled."
      end
    end
  end
end
