# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets.csv"
@jira_tickets = csv_to_array(tickets_jira_csv)

h = {}
total = 0
@jira_tickets.each do |ticket|
  next if ticket['result'] == 'OK'
  messages = ticket['message'].split("\n\n")
  total += 1
  messages.each do |message|
    if h[message]
      h[message] += 1
    else
      h[message] = 1
    end
  end
end

puts "Total: #{total}"
h.each do |key, value|
  puts "#{value}: '#{key}'"
end
