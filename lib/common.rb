# frozen_string_literal: true

require 'json'
require 'csv'
require 'fileutils'
require 'dotenv/load'
require 'rest-client'
require 'base64'
require 'date'

version = File.read(".ruby-version")
unless RUBY_VERSION.start_with?(version)
  puts "Ruby version = '#{version}' is required, got #{RUBY_VERSION} run the following command first:"
  puts "rvm use #{version}"
  exit
end

@debug = ENV['DEBUG'] == 'true'

ASSEMBLA_SPACE = ENV['ASSEMBLA_SPACE'].freeze

ASSEMBLA_API_HOST = ENV['ASSEMBLA_API_HOST'].freeze
ASSEMBLA_API_KEY = ENV['ASSEMBLA_API_KEY'].freeze
ASSEMBLA_API_SECRET = ENV['ASSEMBLA_API_SECRET'].freeze
ASSEMBLA_HEADERS = { 'X-Api-Key': ASSEMBLA_API_KEY, 'X-Api-Secret': ASSEMBLA_API_SECRET }.freeze

ASSEMBLA_SKIP_ASSOCIATIONS = (ENV['ASSEMBLA_SKIP_ASSOCIATIONS'] || '').split(',').push('unknown')

ASSEMBLA_TYPES_EXTRA = (ENV['ASSEMBLA_TYPES_EXTRA'] || '').split(',')

ASSEMBLA_TICKET_REPORT = ENV['ASSEMBLA_TICKET_REPORT'] || 0

ASSEMBLA_TIMEZONE = ENV['ASSEMBLA_TIMEZONE'] || '+0100'
unless ASSEMBLA_TIMEZONE.match?(/^\+\d{4}$/)
  puts "Invalid ASSEMBLA_TIMEZONE='#{ASSEMBLA_TIMEZONE}', please correct in the .env file"
  exit
end

JIRA_API_BASE = ENV['JIRA_API_BASE'].freeze

unless %r{^https?://}.match?(JIRA_API_BASE)
  puts "Invalid value JIRA_API_BASE='#{JIRA_API_BASE}', must start with 'https?://' (see .env file)"
  exit
end

JIRA_API_HOST = "#{JIRA_API_BASE}/#{ENV['JIRA_API_HOST']}"
JIRA_API_ADMIN_USER = ENV['JIRA_API_ADMIN_USER'].freeze
JIRA_API_ADMIN_PASSWORD = ENV['JIRA_API_ADMIN_PASSWORD'].freeze
JIRA_API_KEY = ENV['JIRA_API_KEY'].freeze
JIRA_API_ADMIN_ACCOUNT_ID = ENV['JIRA_API_ADMIN_ACCOUNT_ID'].freeze
JIRA_API_ADMIN_EMAIL = ENV['JIRA_API_ADMIN_EMAIL'].freeze
JIRA_API_ADMIN_GROUP = (ENV['JIRA_API_ADMIN_GROUP'] || 'jira-administrators').freeze
JIRA_API_DEFAULT_EMAIL = (ENV['JIRA_API_DEFAULT_EMAIL'] || 'example.org').gsub(/^@/, '').freeze
JIRA_API_UNKNOWN_USER = (ENV['JIRA_API_UNKNOWN_USER'] || 'unknown.user').freeze
JIRA_API_LEAD_ACCOUNT_ID = ENV['JIRA_API_LEAD_ACCOUNT_ID'].freeze

JIRA_API_IMAGES_THUMBNAIL = (ENV['JIRA_API_IMAGES_THUMBNAIL'] || 'description:false,comments:true').freeze
JIRA_API_USER_GROUPS = (ENV['JIRA_API_USER_GROUPS'] || 'administrators,jira-administrators,jira-core-users,site-admins,jira-software-users').freeze

JIRA_API_PROJECT_NAME = ENV['JIRA_API_PROJECT_NAME'].freeze
JIRA_API_PROJECT_KEY = ENV['JIRA_API_PROJECT_KEY'].freeze

# Jira project type us 'scrum' by default
JIRA_API_PROJECT_TYPE = (ENV['JIRA_API_PROJECT_TYPE'] || 'scrum').freeze

URL_JIRA_SERVERINFO = "#{JIRA_API_HOST}/serverInfo"
URL_JIRA_PROJECTS = "#{JIRA_API_HOST}/project"
URL_JIRA_USERS = "#{JIRA_API_HOST}/users/search"
URL_JIRA_USER_ACCOUNT_ID = "#{JIRA_API_HOST}/user/bulk/migration"
URL_JIRA_ISSUE_TYPES = "#{JIRA_API_HOST}/issuetype"
URL_JIRA_PRIORITIES = "#{JIRA_API_HOST}/priority"
URL_JIRA_RESOLUTIONS = "#{JIRA_API_HOST}/resolution"
URL_JIRA_ROLES = "#{JIRA_API_HOST}/role"
URL_JIRA_STATUSES = "#{JIRA_API_HOST}/status"
URL_JIRA_FIELDS = "#{JIRA_API_HOST}/field"
URL_JIRA_ISSUES = "#{JIRA_API_HOST}/issue"
URL_JIRA_ISSUELINK_TYPES = "#{JIRA_API_HOST}/issueLinkType"
URL_JIRA_ISSUELINKS = "#{JIRA_API_HOST}/issueLink"
URL_JIRA_FILTERS = "#{JIRA_API_HOST}/filter"
URL_JIRA_SCREENS = "#{JIRA_API_HOST}/screens"

# JIRA_API_SPACE_TO_PROJECT=europeana-npc:EC,europeana-apis:EA
JIRA_API_SPACE_TO_PROJECT = ENV['JIRA_API_SPACE_TO_PROJECT']

JIRA_API_BROWSE_ISSUE = ENV['JIRA_API_BROWSE_ISSUE'] || 'browse/[:jira-ticket-key]'
JIRA_API_BROWSE_COMMENT = ENV['JIRA_API_BROWSE_COMMENT'] || 'browse/[:jira-ticket-key]?focusedCommentId=[:jira-comment-id]&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-[:jira-comment-id]'

JIRA_ISSUE_DEFAULT_TYPE = ENV['JIRA_ISSUE_DEFAULT_TYPE'] || nil

JIRA_API_STATUSES = ENV['JIRA_API_STATUSES']

MAX_RETRY = 3

# By default we skip empty (body = "" or nil) and commit comments (contains 'Commit: [[r:...]]' text)
JIRA_API_SKIP_EMPTY_COMMENTS = ENV['JIRA_API_SKIP_EMPTY_COMMENTS'] == 'true'
JIRA_API_SKIP_COMMIT_COMMENTS = ENV['JIRA_API_SKIP_COMMIT_COMMENTS'] == 'true'

# Bitbucket transformations for commit messages
BITBUCKET_REPO_URL = ENV['BITBUCKET_REPO_URL']
BITBUCKET_REPO_TABLE = ENV['BITBUCKET_REPO_TABLE']
BITBUCKET_REPO_CONVERSIONS = ENV['BITBUCKET_REPO_CONVERSIONS'] || 'data/bitbucket-repo-conversions.csv'

# Mangle external emails not ending with the following suffixes, concerting to lowercase.
MANGLE_EXTERNAL_EMAILS = ENV['MANGLE_EXTERNAL_EMAILS'] == 'true'
MANGLE_EXTERNAL_EMAILS_NOT = (ENV['MANGLE_EXTERNAL_EMAILS_NOT'] || '').split(',').map(&:downcase)
MANGLE_EXTERNAL_EMAILS_NOT_IGNORE = (ENV['MANGLE_EXTERNAL_EMAILS_NOT_IGNORE'] || '').split(',').map(&:downcase)

def csv_to_array(pathname)
  csv = CSV::parse(File.open(pathname) { |f| f.read })
  fields = csv.shift
  fields = fields.map { |f| f.downcase.tr(' ', '_') }
  csv.map { |record| Hash[*fields.zip(record).flatten] }
end

def write_csv_file(filename, results)
  puts filename
  CSV.open(filename, 'wb') do |csv|
    # Scan whole file to collect all possible field names so that
    # the list of columns is complete.
    fields = []
    results.each do |result|
      result.keys.each do |field|
        fields << field unless fields.include?(field)
      end
    end
    csv << fields
    results.each do |result|
      row = []
      fields.each do |field|
        row.push(result[field])
      end
      csv << row
    end
  end
end

def write_csv_file_append(filename, results, header)
  CSV.open(filename, 'a') do |csv|
    # Scan whole file to collect all possible field names so that
    # the list of columns is complete.
    fields = []
    results.each do |result|
      result.keys.each do |field|
        fields << field unless fields.include?(field)
      end
    end
    csv << fields if header
    results.each do |result|
      row = []
      fields.each do |field|
        row.push(result[field])
      end
      csv << row
    end
  end
end

def normalize_name(name)
  name.downcase.tr(' /_', '-')
end

OUTPUT_DIR = ENV['DATA_DIR'] || 'data'

def output_dir(name, branch)
  "#{OUTPUT_DIR}/#{branch}/#{normalize_name(name)}"
end

def output_dir_assembla(name)
  output_dir(name, 'assembla')
end

def output_dir_confluence(name)
  output_dir(name, 'confluence')
end

def output_dir_jira(name)
  uri = URI(JIRA_API_HOST)
  host = uri.host
  port = uri.port
  hn = "#{host.tr('.', '-')}-#{port}"
  output_dir("#{name}/#{hn}", 'jira')
end

OUTPUT_DIR_ASSEMBLA = output_dir_assembla(ASSEMBLA_SPACE)
OUTPUT_DIR_JIRA = output_dir_jira(ASSEMBLA_SPACE)
OUTPUT_DIR_JIRA_ATTACHMENTS = "#{OUTPUT_DIR_JIRA}/attachments"

# Ensure that all of the required directories exist, otherwise create them.
[OUTPUT_DIR, OUTPUT_DIR_ASSEMBLA, OUTPUT_DIR_JIRA, OUTPUT_DIR_JIRA_ATTACHMENTS].each do |dir|
  FileUtils.mkdir_p(dir) unless File.directory?(dir)
end

# The following custom fields MUST be defined AND associated with the proper screens
CUSTOM_FIELD_NAMES = [
  'Assembla-Id',
  'Assembla-Created-On',
  'Assembla-Due-Date',
  'Assembla-Milestone',
  'Assembla-Status',
  'Assembla-Reporter',
  'Assembla-Assignee',
  'Assembla-Completed',
  'Assembla-Estimate', # => 0=None, 1=Small, 3=Medium, 7=Large
  'Assembla-Worked',
  'Assembla-Remaining',
  'Assignee',
  'Epic Link',
  'Epic Name',
  'Labels',
  'Rank',
  'Resolution',
  'Sprint',
  'Story Points',
  # IMPORTANT: You might have to comment out the following line to get things working.
  'Time Tracking'
].freeze

JIRA_AGILE_HOST = "#{JIRA_API_BASE}/#{ENV['JIRA_AGILE_HOST']}"
URL_JIRA_BOARDS = "#{JIRA_AGILE_HOST}/board"
URL_JIRA_SPRINTS = "#{JIRA_AGILE_HOST}/sprint"
URL_JIRA_ISSUE_RANKS = "#{JIRA_AGILE_HOST}/issue/rank"
URL_JIRA_EPICS = "#{JIRA_AGILE_HOST}/epic"

# GET /rest/api/2/serverInfo
def jira_get_server_type

  serverinfo_csv = "#{OUTPUT_DIR_JIRA}/jira-serverinfo.csv"
  unless File.exist?(serverinfo_csv)
    url = URL_JIRA_SERVERINFO
    begin
      response = RestClient::Request.execute(method: :get, url: url)
      serverinfo = JSON.parse(response.body)
      puts "GET #{url} => OK"
      write_csv_file(serverinfo_csv, [serverinfo])
    rescue RestClient::ExceptionWithResponse => e
      message = rest_client_exception(e, 'GET', url)
      puts "GET #{url} => NOK (#{message})"
    rescue => e
      puts "GET #{url} => NOK (#{e.message})"
    end
  end
  serverinfo = csv_to_array(serverinfo_csv)[0]
  server_type = serverinfo['deploymenttype'].downcase
  server_type = 'hosted' if server_type == 'server'
  puts "\nServer type = #{server_type}"
  server_type
end

JIRA_SERVER_TYPE = jira_get_server_type

unless /cloud|hosted/.match?(JIRA_SERVER_TYPE)
  puts "Invalid value JIRA_SERVER_TYPE='#{JIRA_SERVER_TYPE}', must be 'cloud' or 'hosted'"
  exit
end

base64_admin = if JIRA_SERVER_TYPE == 'hosted'
                 Base64.strict_encode64(JIRA_API_ADMIN_USER + ':' + JIRA_API_ADMIN_PASSWORD)
               else
                 # Base64.strict_encode64(JIRA_API_ADMIN_EMAIL + ':' + JIRA_API_ADMIN_PASSWORD)
                 Base64.strict_encode64(JIRA_API_ADMIN_EMAIL + ':' + JIRA_API_KEY)
               end

JIRA_HEADERS_ADMIN = {
  'Authorization': "Basic #{base64_admin}",
  'Content-Type': 'application/json; charset=utf-8',
  'Accept': 'application/json'
}.freeze

# Assuming that the user name is the same as the user password
# For the cloud we use the email otherwise login
def headers_user_login(user_login, user_email)
  return JIRA_HEADERS_ADMIN if JIRA_SERVER_TYPE == 'hosted'
  { 'Authorization': "Basic #{Base64.strict_encode64(user_login + ':' + user_login)}", 'Content-Type': 'application/json; charset=utf-8' }
  # { 'Authorization': "Basic #{Base64.strict_encode64(user_email + ':' + JIRA_API_KEY).gsub(/\n/, '')}", 'Content-Type': 'application/json; charset=utf-8' }
end

def get_hierarchy_type(n)
  case n.to_i
  when 0
    'No plan level'
  when 1
    'Subtask'
  when 2
    'Story'
  when 3
    'Epic'
  else
    "Unknown (#{n})"
  end
end

def hierarchy_type_epic(n)
  get_hierarchy_type(n) == 'Epic'
end

def get_tickets_created_on
  env = ENV['TICKETS_CREATED_ON']
  return nil unless env
  begin
    tickets_created_on = Date.strptime(env, '%Y-%m-%d')
  rescue
    goodbye("File '.env' contains an invalid date for ENV['TICKETS_CREATED_ON']='#{env}'")
  end
  tickets_created_on
end

def item_newer_than?(item, date)
  item_date = item['created_on'] || item['created_at']
  goodbye('Item created date cannot be found') unless item_date
  DateTime.parse(item_date) > date
end

def date_format_yyyy_mm_dd(dt)
  return dt unless dt.is_a?(String) && dt.length.positive?
  begin
    date = DateTime.parse(dt)
  rescue
    return dt
  end
  year = date.year
  month = format('%02d', date.month)
  day = format('%02d', date.day)
  "#{year}-#{month}-#{day}"
end

def date_format_datetime(dt)
  # Converts 'yyyy-mm-ddThh:mm:ss.000Z' to 'yyyy-mm-dd hh:mm:ss'
  return dt unless dt.is_a?(String) && dt.length.positive?
  dt.sub(/\.[^.]*$/, '').tr('T', ' ')
end

def date_time(dt)
  return dt unless dt.is_a?(String) && dt.length.positive?
  begin
    date = DateTime.parse(dt)
  rescue
    return dt
  end
  day = format('%02d', date.day)
  month = %w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)[date.month - 1]
  year = date.year
  hour = format('%02d', date.hour)
  minute = format('%02d', date.minute)
  "#{day} #{month} #{year} #{hour}:#{minute}"
end

def ticket_to_s(ticket)
  ticket.delete_if { |k| k =~ /summary|description/ }.inspect
end

def build_counter(opts)
  opts[:counter] ? "[#{opts[:counter]}/#{opts[:total]}] " : ''
end

def http_request(url, opts = {})
  response = ''
  counter = build_counter(opts)
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: ASSEMBLA_HEADERS)
    count = get_response_count(response)
    puts "#{counter}GET #{url} => OK (#{count})"
  rescue => e
    if e.class == RestClient::NotFound && e.response.match?(/Tool not found/i)
      puts "#{counter}GET #{url} => OK (0)"
    else
      message = "#{counter}GET #{url} => NOK (#{e.message})"
      if opts[:continue_onerror]
        puts message
      else
        goodbye(message)
      end
    end
  end
  response
end

def get_response_count(response)
  return 0 if response.nil? || !response.is_a?(String) || response.length.zero?
  begin
    json = JSON.parse(response)
    return 0 unless json.is_a?(Array)
    return json.length
  rescue
    return 0
  end
end

def assembla_get_spaces
  response = http_request("#{ASSEMBLA_API_HOST}/spaces")
  result = JSON.parse(response.body)
  result&.each do |r|
    r.delete_if { |k, _| k.to_s =~ /tabs_order/i }
  end
  result
end

def get_space(name)
  spaces = csv_to_array("#{OUTPUT_DIR_ASSEMBLA}/spaces.csv")
  space = spaces.detect { |s| s['name'] == name }
  unless space
    goodbye("Couldn't find space with name = '#{name}'")
  end
  space
end

# TODO: Similar to get_ticket_attr() in 02-assembla_export_tickets.rb (refactor)
def get_items(items, space)
  items.each do |item|
    url = "#{ASSEMBLA_API_HOST}/spaces/#{space['id']}/#{item[:name]}"
    if item[:q]
      url += "?#{item[:q]}"
      if item[:q] =~ /per_page=(\d+)/
        more_pages = true
        per_page = $1.to_i
      else
        more_pages = false
      end
    end
    page = 1
    item[:results] = []
    in_progress = true
    while in_progress
      in_progress = false
      full_url = url
      full_url += "&page=#{page}" if more_pages
      response = http_request(full_url)
      count = get_response_count(response)
      if count.positive?
        JSON.parse(response).each do |rec|
          item[:results] << rec
        end
        if more_pages && count == per_page
          page += 1
          in_progress = true
        end
      end
    end
  end
  items
end

def create_csv_files(space, items)
  items = [items] unless items.is_a?(Array)
  items.each do |item|
    create_csv_file(space, item)
  end
  puts "#{space['name']} #{items.map { |item| item[:name] }.to_json} => DONE"
end

def create_csv_file(space, item)
  dirname = get_output_dirname(space, 'assembla')
  filename = "#{dirname}/#{normalize_name(item[:name])}.csv"
  write_csv_file(filename, item[:results])
end

def export_assembla_items(list)
  space = get_space(ASSEMBLA_SPACE)
  items = get_items(list, space)
  create_csv_files(space, items)
end

def get_output_dirname(space, dir = nil)
  dirname = "#{OUTPUT_DIR}/#{dir ? (normalize_name(dir) + '/') : ''}#{normalize_name(space['name'])}"
  FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
  dirname
end

# TODO: not used so remove.
def jira_check_unknown_user(b)
  puts "\nUnknown user:" if b
  if JIRA_API_UNKNOWN_USER && JIRA_API_UNKNOWN_USER.length
    # user = jira_get_user(JIRA_API_UNKNOWN_USER, false)
    user = jira_get_user(JIRA_API_LEAD_ACCOUNT_ID, false)
    if user
      goodbye("Please activate Jira unknown user '#{JIRA_API_UNKNOWN_USER}'") unless user['active']
    else
      goodbye("Cannot find Jira unknown user '#{JIRA_API_UNKNOWN_USER}', make sure that has been created and enabled")
    end
  else
    goodbye("Please define 'JIRA_API_UNKNOWN_USER' in the .env file")
  end
end

def jira_build_project_key(project_name)
  # Max. length = 10
  key = project_name.split(' ').map { |w| w[0].upcase }.join
  key = project_name.upcase if key.length == 1
  key = key[0..9] if key.length > 10
  key
end

# Create project and scrum/kanban board
# POST /rest/api/2/project
# {
#   key: project_key,
#   name: project_name,
#   projectTypeKey: 'software',
#   description: project_description,
#   projectTemplateKey: "com.pyxis.greenhopper.jira:gh-#{type}-template",
#   lead: username
# }
#
# where '#{type}' must be either 'scrum' or 'kanban'
#
def jira_create_project(project_name, project_key, project_type)
  goodbye("Invalid project type=#{project_type}, must be 'scrum' or 'kanban'") unless %w(scrum kanban).include?(project_type)
  result = nil
  key = jira_build_project_key(project_key)
  account_id = jira_get_user_account_id(JIRA_API_ADMIN_USER)
  payload = {
    key: key,
    name: project_name,
    projectTypeKey: 'software',
    description: "Description of project '#{project_name}'",
    projectTemplateKey: "com.pyxis.greenhopper.jira:gh-#{project_type}-template",
    # No longer supported.
    # lead: JIRA_API_ADMIN_USER
    leadAccountId: account_id
  }.to_json
  begin
    response = RestClient::Request.execute(method: :post, url: URL_JIRA_PROJECTS, payload: payload, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    puts "POST #{URL_JIRA_PROJECTS} name='#{project_name}', key='#{key}' => OK"
  rescue RestClient::ExceptionWithResponse => e
    error = JSON.parse(e.response)
    message = error['errors'].map { |k, v| "#{k}: #{v}" }.join(' | ')
    puts "POST #{URL_JIRA_PROJECTS} name='#{project_name}', key='#{key}' => NOK (#{message})"
  rescue => e
    puts "POST #{URL_JIRA_PROJECTS} name='#{project_name}', key='#{key}' => NOK (#{e.message})"
  end
  result
end

#def jira_get_all_users
#  result = nil
#  url = URL_JIRA_USERS
#  begin
#    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
#    result = JSON.parse(response)
#    puts "GET #{url} => OK (#{result.length})"
#  rescue => e
#    puts "GET #{url} => NOK (#{e.message})"
#  end
#  result
#end

def jira_get_user_account_id(username)
  return JIRA_API_LEAD_ACCOUNT_ID unless JIRA_API_LEAD_ACCOUNT_ID.nil?
  result = nil
  account_id = nil
  url = "#{URL_JIRA_USER_ACCOUNT_ID}?username=#{username}"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response)
    if result.kind_of?(Array) && result.length == 1
      account_id = result[0]['accountId']
      puts "GET #{url} => accountId='#{account_id}' OK"
    end
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  account_id
end

def jira_get_projects
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_PROJECTS, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response)
    if result
      result.each do |r|
        r.delete_if { |k, _| k.to_s =~ /expand|self|avatarurls/i }
      end
      puts "GET #{URL_JIRA_PROJECTS} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_PROJECTS} => NOK (#{e.message})"
  end
  result
end

def jira_get_project_by_name(name)
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_PROJECTS, headers: JIRA_HEADERS_ADMIN)
    body = JSON.parse(response.body)
    result = body.detect { |h| h['name'] == name }
    if result
      result.delete_if { |k, _| k =~ /expand|self|avatarurls/i }
      puts "GET #{URL_JIRA_PROJECTS} name='#{name}' => OK"
    end
  rescue => e
    puts "GET #{URL_JIRA_PROJECTS} name='#{name}' => NOK (#{e.message})"
  end
  result
end

def jira_get_priorities
  result = []
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_PRIORITIES, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.each do |r|
        r.delete_if { |k, _| k =~ /self|statuscolor|iconurl/i }
      end
      puts "GET #{URL_JIRA_PRIORITIES} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_PRIORITIES} => NOK (#{e.message})"
  end
  result
end

def jira_get_resolutions
  result = []
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_RESOLUTIONS, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.each do |r|
        r.delete_if { |k, _| k =~ /self/i }
      end
      puts "GET #{URL_JIRA_RESOLUTIONS} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_RESOLUTIONS} => NOK (#{e.message})"
  end
  result
end

def jira_get_roles
  result = []
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_ROLES, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.each do |r|
        r.delete_if { |k, _| k =~ /self/i }
      end
      puts "GET #{URL_JIRA_ROLES} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_ROLES} => NOK (#{e.message})"
  end
  result
end

def jira_get_statuses
  result = []
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_STATUSES, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.each do |r|
        r.delete_if { |k, _| k =~ /self|iconurl|statuscategory/i }
      end
      puts "GET #{URL_JIRA_STATUSES} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_STATUSES} => NOK (#{e.message})"
  end
  result
end

def jira_get_issue(issue_id)
  result = nil
  url = "#{URL_JIRA_ISSUES}/#{issue_id}"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.delete_if { |k, _| k =~ /self|expand/i }
      puts "GET #{url} => OK"
    end
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'GET', url)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

def jira_get_issue_comment(issue_id, comment_id)
  result = nil
  url = "#{URL_JIRA_ISSUES}/#{issue_id}/comment/#{comment_id}"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.delete_if { |k, _| k =~ /self|expand/i }
      puts "GET #{url} => OK"
    end
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'GET', url)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

def jira_get_issue_comments(issue_id)
  result = nil
  url = "#{URL_JIRA_ISSUES}/#{issue_id}/comment"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    if result
      result.delete_if { |k, _| k =~ /self|expand/i }
      result = result['comments']
      puts "GET #{url} => OK"
    end
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'GET', url)
  rescue => e
    puts "GET #{url} => NOK (#{e.message})"
  end
  result
end

def jira_get_issue_types
  result = nil
  # Only want issues types for current project
  jira_project = jira_get_project_by_name(JIRA_API_PROJECT_NAME)
  begin
    url = "#{URL_JIRA_ISSUE_TYPES}/project?projectId=#{jira_project['id']}"
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response)
    if result
      result.each do |r|
        r.delete_if { |k, _| k.to_s =~ /self|iconurl|avatarid/i }
      end
      puts "GET #{URL_JIRA_ISSUE_TYPES} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_ISSUE_TYPES} => NOK (#{e.message})"
  end
  result
end

def jira_get_issuelink_types
  result = nil
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_ISSUELINK_TYPES, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response)
    result = result['issueLinkTypes']
    if result
      result.each do |r|
        r.delete_if { |k, _| k.to_s =~ /self/i }
      end
      puts "GET #{URL_JIRA_ISSUELINK_TYPES} => OK (#{result.length})"
    end
  rescue => e
    puts "GET #{URL_JIRA_ISSUELINK_TYPES} => NOK (#{e.message})"
  end
  result
end

def jira_create_custom_field(name, description, type, searcherKey)
  result = nil
  payload = {
    name: name,
    description: description,
    type: type,
    searcherKey: searcherKey
  }.to_json
  begin
    response = RestClient::Request.execute(method: :post, url: URL_JIRA_FIELDS, payload: payload, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    puts "POST #{URL_JIRA_FIELDS} name='#{name}' description='#{description}' type='#{type}' searcherKey='#{searcherKey}' => OK (#{result['id']})"
  rescue RestClient::ExceptionWithResponse => e
    error = JSON.parse(e.response)
    message = error['errorMessages'].join(' | ')
    puts "POST #{URL_JIRA_FIELDS} name='#{name}' description='#{description}' type='#{type}' searcherKey='#{searcherKey}' => NOK (#{message})"
  rescue => e
    puts "POST #{URL_JIRA_FIELDS} name='#{name}' description='#{description}' type='#{type}' searcherKey='#{searcherKey}' => NOK (#{e.message})"
  end
  result
end

def jira_get_fields
  result = []
  begin
    response = RestClient::Request.execute(method: :get, url: URL_JIRA_FIELDS, headers: JIRA_HEADERS_ADMIN)
    result = JSON.parse(response.body)
    puts "GET #{URL_JIRA_FIELDS} => OK (#{result.length})"
  rescue => e
    puts "GET #{URL_JIRA_FIELDS} => NOK (#{e.message})"
  end
  result
end

def jira_create_user(user)
  result = nil
  url = "#{JIRA_API_HOST}/user"
  display_name = user[:assemblaName]
  email_address = user[:emailAddress]
  if email_address.nil? || email_address.length.zero?
    username = user[:assemblaLogin]
    if username.nil? || username.length.zero?
      username = display_name.tr(' ', '_')
    end
    email_address = "#{username}@#{JIRA_API_DEFAULT_EMAIL}"
  end
  payload = {
    emailAddress: email_address,
    displayName: display_name,
    # Only works if no password
    # https://jira.atlassian.com/browse/JRACLOUD-67680
    notification: false
  }.to_json
  begin
    response = RestClient::Request.execute(method: :post, url: url, payload: payload, headers: JIRA_HEADERS_ADMIN, timeout: 30)
    body = JSON.parse(response.body)
    body.delete_if { |k, _| k =~ /self|avatarurls|timezone|locale|groups|applicationroles|expand/i }
    puts "POST #{url} name='#{display_name}' => OK (#{body.to_json})"
    result = body
  rescue RestClient::ExceptionWithResponse => e
    if e.class == RestClient::InternalServerError
      puts "POST #{url} name='#{display_name}' => NOK (#{e}) please retry"
    end
    error = JSON.parse(e.response)
    message = if error['errorMessages']
                error['errorMessages'].join(' | ')
              else
                error['errors'].map { |k, v| "#{k}: #{v}" }.join(' | ')
              end
    puts "POST #{url} name='#{display_name}' => NOK (#{message})"
  rescue => e
    puts "POST #{url} name='#{display_name}' => NOK (#{e.message})"
  end
  result
end

def jira_get_user(accountId, groups)
  result = nil
  url = "#{JIRA_API_HOST}/user?accountId=#{accountId}"
  url += '&expand=groups' if groups
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    body = JSON.parse(response.body)
    body.delete_if { |k, _| k =~ /self|avatarurls|timezone|locale|applicationroles|expand/i }
    puts "GET #{url} => OK (#{body.to_json})"
    result = body
  rescue => e
    if e.class == RestClient::NotFound && JSON.parse(e.response)['errorMessages'][0] =~ /does not exist/
      puts "GET #{url} => NOK (does not exist)"
    else
      goodbye("GET #{url} => NOK (#{e.message})")
    end
  end
  result
end

def jira_delete_user(user)
  account_id = user['accountId']
  display_name = user['displayName']
  active = user['active']
  url = "#{JIRA_API_HOST}/user?accountId=#{account_id}"
  begin
    RestClient::Request.execute(method: :delete, url: url, headers: JIRA_HEADERS_ADMIN)
    puts "DELETE #{url} account_id='#{account_id}' display_name='#{display_name}' active='#{active}' => OK"
  rescue => e
    puts "DELETE #{url} account_id='#{account_id}' display_name='#{display_name}' active='#{active}' => NOK (#{e.inspect})"
  end
end

def jira_get_group(group)
  result = nil
  url = "#{JIRA_API_HOST}/group/member?groupname=#{group}&startAt=0&maxResults=1000"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    body = JSON.parse(response.body)
    result = body.values[5]
    puts "GET #{url}  => OK (#{result.length})"
    result
  rescue => e
    if e.class == RestClient::NotFound && JSON.parse(e.response)['errorMessages'][0] =~ /does not exist/
      puts "GET #{url} => NOK (does not exist)"
    else
      goodbye("GET #{url} => NOK (#{e.message})")
    end
  end
  result
end

def jira_remove_user_from_group(groupname, user)
  result = nil
  account_id = user['accountId']
  url = "#{JIRA_API_HOST}/group/user?groupname=#{groupname}&accountId=#{account_id}"
  begin
    response = RestClient::Request.execute(method: :delete, url: url, headers: JIRA_HEADERS_ADMIN)
    puts "DELETE #{url}  => OK"
  rescue => e
    puts "DELETE #{url} => NOK (#{e.message})"
  end
end

def jira_get_board_by_project_name(project_name)
  result = nil
  url = URL_JIRA_BOARDS
  key = JIRA_API_PROJECT_KEY
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: JIRA_HEADERS_ADMIN)
    body = JSON.parse(response.body)
    # max_results = body['maxResults'].to_i
    # start_at = body['startAt'].to_i
    # is_last = body['isLast']
    values = body['values']
    if values
      result = values.detect { |h| h['name'].match?(/^#{key}/) }
      if result
        result.delete_if { |k, _| k =~ /self/i }
        puts "GET #{url} name='#{project_name}', key='#{key}' => FOUND"
      else
        puts "GET #{url} name='#{project_name}', key='#{key}' => NOT FOUND"
      end
    end
  rescue => e
    puts "GET #{url} name='#{project_name}', key='#{key}' => NOK (#{e.message})"
  end
  result
end

def goodbye(message)
  puts "\nGOODBYE: #{message}"
  exit
end

def warning(message)
  puts "WARNING: #{message}"
end

# Markdown conversion
#
# See: https://github.com/kgish/assembla-to-jira/blob/develop/README.md#markdown
#

# Split content into an array of lines and retain all empty lines,
# including the (possible) last empty line.
def split_into_lines(content)
  "#{content}\n".lines.map(&:chomp)
end

@cache_markdown_names = {}

def markdown_name(name, user_ids)
  if name[0] == '@'
    # Regex isn't perfect, catch email addresses and names that
    # begin with a digit, just in case.
    return name unless /@[^.]+\.[^>]+>/.match(name).nil?
    return name unless /\d/.match(name[1]).nil?
    name = name[1..-1].sub(/@.*$/, '').strip
  elsif name[0..6] == '[[user:'
    name = name[7..-3].gsub(/\|.*$/, '').strip
  else
    goodbye("markdown_name(name='#{name}') has unknown format")
  end
  return @cache_markdown_names[name] if @cache_markdown_names[name]
  user_id = user_ids[name]
  result = user_id ? "[~accountid:#{user_id}]" : "[#{name}]"
  warning "Reformat markdown name='#{name}' => NOT FOUND" unless user_id
  @cache_markdown_names[name] = result
end

@cache_markdown_ticket_links = {}

def markdown_ticket_link(ticket, tickets, strikethru = false)
  return ticket unless ticket[0] == '#'
  ticket_number = ticket[1..-1]
  return @cache_markdown_ticket_links[ticket_number] if @cache_markdown_ticket_links[ticket_number]
  key = tickets[ticket_number]
  if key
    result = key
  else
    result = "##{ticket_number}"
    if strikethru
      result = "-#{result}-"
    end
    warning "Reformat markdown ticket='#{ticket_number}' => NOT FOUND"
  end
  @cache_markdown_ticket_links[ticket_number] = result
end

@content_types_thumbnail = {}

JIRA_API_IMAGES_THUMBNAIL.split(',').each do |item|
  content_type, thumbnail = item.split(':')
  @content_types_thumbnail[content_type] = thumbnail !~ /false|no|0/i
  # puts "@content_types_thumbnail['#{content_type}'] = #{@content_types_thumbnail[content_type]}"
end

def markdown_image(image, images, content_type)
  _, id, text = image[2...-2].split(/:|\|/)
  name = images[id]
  if name
    result = "!#{name}#{@content_types_thumbnail[content_type] ? '|thumbnail' : ''}!"
  else
    result = image
    warning "Reformat markdown image='#{image}', id='#{id}', text='#{text}' => NOT FOUND"
  end
  result
end

def reformat_markdown(content, opts = {})
  return content if content.nil? || content.length.zero?
  user_ids = opts[:user_ids]
  images = opts[:images]
  content_type = opts[:content_type]
  tickets = opts[:tickets]
  strikethru = opts[:strikethru]
  lines = split_into_lines(content)
  markdown = []
  lines.each do |line|
    if line.strip.length.zero?
      markdown << line
      next
    end
    line.gsub!(/#(\d+)\b/) { |ticket| markdown_ticket_link(ticket, tickets, strikethru) } if tickets
    markdown << line.
      gsub(/<pre><code>/i, '{code:java}').
      gsub(/<\/code><\/pre>/i, '{code}').
      gsub(/\[\[url:(.*?)\|(.*?)\]\]/i, '[\2|\1]').
      gsub(/\[\[url:(.*?)\]\]/i, '[\1|\1]').
      gsub(/<code>(.*?)<\/code>/i, '{{\1}}').
      gsub(/@([^@]*)@( |$)/, '{{\1}}\2').
      gsub(/@([a-z._-]*)/i) { |name| markdown_name(name, user_ids) }.
      gsub(/\[\[user:(.*?)(\|(.*?))?\]\]/i) { |name| markdown_name(name, user_ids) }.
      gsub(/\[\[image:(.*?)(\|(.*?))?\]\]/i) { |image| markdown_image(image, images, content_type) }
  end
  markdown.join("\n")
end

def rest_client_exception(e, method, url, payload = {})
  message = 'Unknown error'
  begin
    err = JSON.parse(e.response)
    if err['errors'] && !err['errors'].empty?
      message = err['errors'].map { |k, v| "#{k}: #{v}" }.join(' | ')
    elsif err['errorMessages'] && !err['errorMessages'].empty?
      message = err['errorMessages'].join(' | ')
    elsif err['error']
      message = err['error']
      if err['error_description']
        message += ": #{err['error_description']}"
      end
    elsif err['status-code']
      message = "Status code: #{err['status-code']}"
    else
      message = e.to_s
    end
  rescue
    message = e.to_s
  end
  puts "#{method} #{url}#{payload.empty? ? '' : ' ' + payload.inspect} => NOK (#{message})"
  message
end

def assembla_estimate_to_jira_size(estimate)
  return case estimate.to_i
         when 0
           'None'
         when 1
           'Small'
         when 3
           'Medium'
         when 7
           'Large'
         else
           'None'
         end
end

def confirm(message)
  confirm_token = rand(36 ** 6).to_s(36)
  puts message
  puts "Enter '#{confirm_token}' to confirm:"
  input = STDIN.gets.chomp
  yes = input == confirm_token
  puts yes ? 'Okay, you asked for it ...' : 'Cancelled'
  yes
end
