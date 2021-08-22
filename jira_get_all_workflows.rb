# frozen_string_literal: true

load './lib/common.rb'

@all_worklows = []
def jira_get_all_workflows
  workflows = []
  start_at = 0
  max_results = 50
  is_last = false
  until is_last
    url = "#{JIRA_API_HOST.sub('/rest/api/2', '/rest/api/3')}/workflow/search?startAt=#{start_at}&maxResults=#{max_results}"
    begin
      response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
      result = JSON.parse(response.body)
      values = result['values']
      total = result['total']
      is_last = result['isLast']
      values.each do |value|
        workflows << value
      end
      puts "GET #{url} => OK (#{total})"
      start_at += max_results unless is_last
    rescue => e
      puts "GET #{url} => NOK (#{e.message})"
      is_last = true
    end
  end
  workflows
end

workflows = jira_get_all_workflows

puts workflows.inspect

