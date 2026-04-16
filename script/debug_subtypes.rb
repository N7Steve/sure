Account.includes(:accountable).where(accountable_type: "Investment").find_each do |acc|
  puts "Account Name: #{acc.name}"
  puts "Account Subtype (Direct SQL): #{acc.read_attribute(:subtype).inspect}"
  puts "Accountable Subtype (Investment): #{acc.accountable&.read_attribute(:subtype).inspect}"
  puts "Account#subtype (Delegated): #{acc.subtype.inspect}"
  puts "Supports Trades: #{acc.supports_trades?}"
  puts "-------------------------"
end
