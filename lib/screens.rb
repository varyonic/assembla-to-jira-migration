# frozen_string_literal: true
#

# See: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-type-screen-schemes/#api-rest-api-3-issuetypescreenscheme-mapping-get
# GET /rest/api/3/issuetypescreenscheme/project
# Get issue type screen schemes for projects
def jira_get_project_screens(project_id)
  screens = []
  start_at = 0
  max_results = 50
  is_last = false
  until is_last
    url = "#{JIRA_API_HOST.sub('/rest/api/2', '/rest/api/3')}/issuetypescreenscheme/project?projectId=#{project_id}&startAt=#{start_at}&maxResults=#{max_results}"
    begin
      response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
      result = JSON.parse(response.body)
      values = result['values']
      total = result['total']
      is_last = result['isLast']
      values.each do |value|
        screens << value
      end
      puts "GET #{url} => OK (#{total})"
      start_at += max_results unless is_last
    rescue => e
      puts "GET #{url} => NOK (#{e.message})"
      is_last = true
    end
  end
  screens
end

def jira_get_screens
  screens = []
  start_at = 0
  max_results = 50
  is_last = false
  until is_last
    url = "#{URL_JIRA_SCREENS}?startAt=#{start_at}&maxResults=#{max_results}"
    begin
      response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
      result = JSON.parse(response.body)
      values = result['values']
      total = result['total']
      is_last = result['isLast']
      values.each do |value|
        screens << value
      end
      puts "GET #{url} => OK (#{total})"
      start_at += max_results unless is_last
    rescue => e
      puts "GET #{url} => NOK (#{e.message})"
      is_last = true
    end
  end
  screens
end

def jira_get_screen_tabs(project_key, screen_id)
  url = "#{URL_JIRA_SCREENS}/#{screen_id}/tabs?projectKey=#{project_key}"
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

def jira_get_screen_available_fields(project_key, screen_id)
  url = "#{URL_JIRA_SCREENS}/#{screen_id}/availableFields?projectKey=#{project_key}"
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

def jira_get_screen_tab_fields(project_key, screen_id, tab_id)
  url = "#{URL_JIRA_SCREENS}/#{screen_id}/tabs/#{tab_id}/fields?projectKey=#{project_key}"
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

# POST /rest/api/2/screens/{screenId}/tabs/{tabId}/fields
# {
#     "fieldId": "summary"
# }
def jira_add_field(screen_id, tab_id, field_id)
  url = "#{URL_JIRA_SCREENS}/#{screen_id}/tabs/#{tab_id}/fields"
  payload = {
    fieldId: field_id
  }.to_json
  result = nil
  begin
    response = RestClient::Request.execute(method: :post, url: url, payload: payload, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    puts "POST #{url} => OK"
  rescue => e
    puts "POST #{url} => NOK (#{e.message})"
  end
  result
end

