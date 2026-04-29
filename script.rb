c = Money::Currency.new('USD')
File.write('currency_methods.txt', c.public_methods.sort.join("\n"))
