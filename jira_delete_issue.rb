# frozen_string_literal: true

load './lib/common.rb'

def jira_delete_ticket(ticket_key)
  result = nil
  url = "#{URL_JIRA_ISSUES}/#{ticket_key}"
  begin
    response = RestClient::Request.execute(method: :delete, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    puts "DELETE #{url} => OK"
  rescue => e
    response = JSON.parse(e.response)
    messages = response['errorMessages']
    puts "DELETE #{url} => NOK #{e.message} (#{messages.join(' | ')})"
  end
  result
end

unless ARGV.length == 1
  goodbye('Missing ticket key, ARGV1=ticket_key')
end
ticket_key = ARGV[0]
goodbye("Invalid ARGV1='#{ticket_key}', must have format 'KEY-number'") unless /^[a-z]+-\d+$/i.match?(ticket_key)

issue = jira_get_issue(ARGV[0])

exit if issue.nil?

id = issue['id']
key = issue['key']
fields = issue['fields']
summary = fields['summary']
description = fields['description']

puts "\nkey='#{key}' id='#{id}' summary"
puts '-----Summary---------'
puts summary
puts '-----Description-----'
puts description
puts '---------------------'

printf "\nWARNING!!! - You are about to delete the issue above, press 'y' to continue: "
prompt = STDIN.gets.chomp
if prompt != 'y'
  puts 'Bye bye ...'
  exit
end

puts "Deleting issue '#{ticket_key}'"
result = jira_delete_ticket(ticket_key)

puts result.inspect unless result.nil?
