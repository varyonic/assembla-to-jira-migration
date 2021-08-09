# frozen_string_literal: true

load './lib/common.rb'

statuses_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/tickets-statuses.csv"
@statuses = csv_to_array(statuses_assembla_csv)

puts "\nTotal statuses: #{@statuses.count}"
@statuses.each do |status|
  puts status['name']
end
