# frozen_string_literal: true

load './lib/common.rb'
load './lib/custom-fields.rb'
load './lib/users-jira.rb'

# Parameters: startAt=n maxResults=m (optional)

@startAt = 1
@maxResults = -1

unless ARGV[0].nil?
  goodbye("Invalid ARGV1='#{ARGV[0]}', must be 'startAt=number' where number > 0") unless /^startAt=([1-9]\d*)$/.match?(ARGV[0])
  m = /^startAt=([1-9]\d*)$/.match(ARGV[0])
  @startAt = m[1].to_i
  unless ARGV[1].nil?
    goodbye("Invalid ARGV2='#{ARGV[1]}', must be 'maxResults=number' where number > 0") unless /^maxResults=([1-9]\d*)$/.match?(ARGV[1])
    m = /^maxResults=([1-9]\d*)$/.match(ARGV[1])
    @maxResults = m[1].to_i
  end
end

puts "\nstartAt: #{@startAt}"
puts "maxResults: #{@maxResults}" if @maxResults != -1

# --- ASSEMBLA Tickets --- #

tickets_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/tickets.csv"
milestones_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/milestones-all.csv"
tags_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/ticket-tags.csv"
associations_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/ticket-associations.csv"

@tickets_assembla = csv_to_array(tickets_assembla_csv)
@milestones_assembla = csv_to_array(milestones_assembla_csv)
@tags_assembla = csv_to_array(tags_assembla_csv)
@associations_assembla = csv_to_array(associations_assembla_csv)

# --- Filter by date if TICKET_CREATED_ON is defined --- #
tickets_created_on = get_tickets_created_on

@nr_milestones = @milestones_assembla.length
puts "\nMilestones: #{@nr_milestones}"
puts "Tags: #{@tags_assembla.length}"
puts "Associations: #{@associations_assembla.length}"

if tickets_created_on
  puts "\nFilter newer than: #{tickets_created_on}"
  tickets_initial = @tickets_assembla.length
  @tickets_assembla.select! { |item| item_newer_than?(item, tickets_created_on) }
  puts "Tickets: #{tickets_initial} => #{@tickets_assembla.length} ∆#{tickets_initial - @tickets_assembla.length}"
else
  puts "\nTickets: #{@tickets_assembla.length}"
end

# --- JIRA Tickets --- #

users_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-users.csv"
issue_types_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-issue-types.csv"
attachments_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-attachments-download.csv"

# @jira_users => assemblaid,assemblalogin,key,accountid,name,emailaddress,displayname,active (downcase)
@jira_users = csv_to_array(users_jira_csv)
@issue_types_jira = csv_to_array(issue_types_jira_csv)
@attachments_jira = File.exist?(attachments_jira_csv) ? csv_to_array(attachments_jira_csv) : []

@list_of_images = {}
@attachments_jira.each do |attachment|
  @list_of_images[attachment['assembla_attachment_id']] = attachment['filename']
end

@assembla_login_to_jira_id = {}
@assembla_login_to_jira_name = {}
@a_user_id_to_j_issue_id = {}
@a_user_id_to_j_user_name = {}

# user: assemblaid,assemblalogin,emailaddress,accountid,accounttype,displayname,active
@jira_users.each do |user|
  @assembla_login_to_jira_id[user['assemblalogin']] = user['accountid']
  # @assembla_login_to_jira_name[user['assemblalogin']] = user['name']
  @assembla_login_to_jira_name[user['assemblalogin']] = user['displayname']
  @a_user_id_to_j_issue_id[user['assemblaid']] = user['accountid']
  @a_user_id_to_j_user_name[user['assemblaid']] = user['displayname']
end

puts "\nAttachments: #{@attachments_jira.length}"
puts

@fields_jira = []

@is_not_a_user = [nil, '']
@cannot_be_assigned_issues = [nil, '']

# Create a list of users who are inactive.
@inactive_jira_users = []
jira_get_all_users.each do |user|
  @inactive_jira_users << user['displayName'] unless user['active']
end

puts "Inactive Jira users: #{@inactive_jira_users.length}"
@inactive_jira_users.each do |name|
  puts "* #{name}"
end

# This is populated as the tickets are created.
@assembla_number_to_jira_key = {}

def jira_get_field_by_name(name)
  @fields_jira.find { |field| field['name'] == name }
end

# 0 - Parent (ticket2 is parent of ticket1 and ticket1 is child of ticket2)
# 5 - Story (ticket2 is story and ticket1 is subtask of the story)
def get_parent_issue(ticket)
  issue = nil
  ticket1_id = ticket['id']
  association = @associations_assembla.find { |assoc| assoc['ticket1_id'] == ticket1_id && assoc['relationship_name'].match(/story|parent/) }
  if association
    ticket2_id = association['ticket2_id']
    issue = @jira_issues.find { |iss| iss[:assembla_ticket_id] == ticket2_id }
  else
    puts "Could not find parent_id for ticket_id=#{ticket1_id}"
  end
  issue
end

def get_labels(ticket)
  labels = ['assembla']
  @tags_assembla.each do |tag|
    if tag['ticket_number'] == ticket['number']
      labels << tag['name'].tr(' ', '-')
    end
  end
  labels
end

def get_milestone(ticket)
  id = ticket['milestone_id']
  name = id && id.length.positive? ? (@milestone_id_to_name[id] || id) : 'unknown milestone'
  { id: id, name: name }
end

def get_issue_type(ticket)
  result = case ticket['hierarchy_type'].to_i
           when 1
             { id: @issue_type_name_to_id['sub-task'], name: 'sub-task' }
           when 2
             { id: @issue_type_name_to_id['story'], name: 'story' }
           when 3
             { id: @issue_type_name_to_id['epic'], name: 'epic' }
           else
             if JIRA_ISSUE_DEFAULT_TYPE
               { id: @issue_type_name_to_id[JIRA_ISSUE_DEFAULT_TYPE], name: JIRA_ISSUE_DEFAULT_TYPE }
             else
               { id: @issue_type_name_to_id['task'], name: 'task' }
             end
           end

  # Ticket type is overruled if summary begins with the type, for example SPIKE or BUG.
  ASSEMBLA_TYPES_EXTRA.each do |s|
    # if ticket['summary'] =~ /^#{s}/i
    if /^#{s}/i.match?(ticket['summary'])
      result = { id: @issue_type_name_to_id[s], name: s }
      break
    end
  end
  result
end

def create_ticket_jira(ticket, counter, total)

  project_id = @project['id']
  ticket_id = ticket['id']
  ticket_number = ticket['number']
  summary = reformat_markdown(ticket['summary'], user_ids: @assembla_login_to_jira_id, images: @list_of_images, content_type: 'summary', tickets: @assembla_number_to_jira_key)
  created_on = ticket['created_on']
  completed_date = ticket['completed_date']
  due_date = ticket['due_date']
  reporter_id = ticket['reporter_id']
  assigned_to_id = ticket['assigned_to_id']
  priority = ticket['priority']
  reporter_name = @a_user_id_to_j_user_name[reporter_id]
  jira_reporter_id = @a_user_id_to_j_issue_id[reporter_id]
  if reporter_name.nil?
    reporter_name = JIRA_API_UNKNOWN_USER
  end
  if assigned_to_id
    assignee_name = @a_user_id_to_j_user_name[assigned_to_id]
    jira_assignee_id = @a_user_id_to_j_issue_id[assigned_to_id]
  else
    assignee_name = nil
  end
  priority_name = @priority_id_to_name[priority]
  status_name = ticket['status']
  story_rank = ticket['importance']
  story_points = ticket['story_importance']
  estimate = ticket['estimate']
  assembla_worked = ticket['total_invested_hours']
  assembla_remaining = ticket['total_working_hours']

  # Prepend the description text with a link to the original assembla ticket on the first line.
  description = "Assembla ticket [##{ticket_number}|#{ENV['ASSEMBLA_URL_TICKETS']}/#{ticket_number}] | "
  author_name = if @is_not_a_user.include?(reporter_name) || reporter_name == JIRA_API_UNKNOWN_USER
                  'unknown'
                else
                  # "[~#{reporter_name}]"
                  "[~accountid:#{jira_reporter_id}]"
                end
  description += "Author #{author_name} | "
  description += "Created on #{date_time(created_on)}\n\n"
  reformatted_description = "#{reformat_markdown(ticket['description'], user_ids: @assembla_login_to_jira_id, images: @list_of_images, content_type: 'description', tickets: @assembla_number_to_jira_key)}"
  description += reformatted_description

  if description.length > 32767
    description = description[0..32760] + '...'
    warning('Ticket description length is greater than 32767 => truncate')
  end

  labels = get_labels(ticket)

  milestone = get_milestone(ticket)

  issue_type = get_issue_type(ticket)

  fields = {
    project: { 'id': project_id },
    summary: summary,
    issuetype: { 'id': issue_type[:id] },
    # reporter: { 'name': reporter_name },
    reporter: { 'id': jira_reporter_id },
    # assignee: { 'name': assignee_name },
    assignee: { 'id': jira_assignee_id },
    priority: { 'name': priority_name },
    # IMPORTANT: You might have to comment out the following line to get things working.
    labels: labels,
    description: description,

    # IMPORTANT: The following custom fields MUST be on the create issue screen for this project
    #  Admin > Issues > Screens > Configure screen > 'PROJECT_KEY: Scrum Default Issue Screen'
    # Assembla

    'Assembla-Id' => ticket_number,
    'Assembla-Created-On' => date_format_datetime(created_on),
    'Assembla-Due-Date' => date_format_datetime(due_date),
    'Assembla-Reporter' => reporter_name,
    'Assembla-Assignee' => assignee_name,
    'Assembla-Status' => status_name,
    'Assembla-Milestone' => @nr_milestones.nonzero? ? milestone[:name] : nil,
    'Assembla-Completed' => date_format_datetime(completed_date)
  }

  # Assembla-Estimate => 0=None, 1=Small, 3=Medium, 7=Large
  jira_size = assembla_estimate_to_jira_size(estimate)
  fields['Assembla-Estimate'] = jira_size

  # Assembla-Worked => hrs
  if assembla_worked.to_i != 0
    fields['Assembla-Worked'] = assembla_worked
  end

  # Assembla-Remaining => hrs
  if assembla_remaining.to_i != 0
    fields['Assembla-Remaining'] = assembla_remaining
  end

  if JIRA_SERVER_TYPE == 'hosted'
    fields['Rank'] = story_rank
  end

  # Reporter is required
  if @is_not_a_user.include?(reporter_name)
    warning("Reporter name='#{reporter_name}' is not a user => RESET '#{JIRA_API_UNKNOWN_USER}'")
    # fields[:reporter][:name] = JIRA_API_UNKNOWN_USER
    fields[:reporter][:id] = JIRA_API_LEAD_ACCOUNT_ID
  elsif @inactive_jira_users.include?(reporter_name)
    warning("Reporter name='#{reporter_name}' is inactive => RESET '#{JIRA_API_UNKNOWN_USER}'")
    # fields[:reporter][:name] = JIRA_API_UNKNOWN_USER
    fields[:reporter][:id] = JIRA_API_LEAD_ACCOUNT_ID
  end

  # Verify assignee
  if @cannot_be_assigned_issues.include?(assignee_name)
    warning("Assignee name='#{assignee_name}' cannot be assigned issues => REMOVE") unless assignee_name.nil? || assignee_name.length.zero?
    fields[:assignee][:id] = JIRA_API_LEAD_ACCOUNT_ID
  elsif @inactive_jira_users.include?(assignee_name)
    warning("Assignee name='#{assignee_name}' is inactive => REMOVE")
    fields[:assignee][:id] = JIRA_API_LEAD_ACCOUNT_ID
  end

  # --- Custom fields Assembla --- #
  #
  # "customfield_10184": { // LIST
  #   "value": "three"
  # },
  # "customfield_10185": "dummy text", // TEXT
  # "customfield_10186": 22.5, // NUMBER
  # "customfield_10175": { // TEAM LIST
  #   "name": "lance1"
  # }
  #
  custom_fields = JSON.parse(ticket['custom_fields'].gsub('=>', ':'))
  custom_fields.each do |k, v|
    next if v.nil? || v.length.zero?
    type = @custom_title_to_type[k]
    value = type == 'Numeric' ? (v.index('.') ? v.to_f : v.to_i) : v
    if %w[List Checkbox].include?(type)
      id = jira_get_list_option_id(k, v)
      if id
        fields[k] = { id: id }
      else
        warning("Unknown custom field type='#{type}' title='#{k}', value='#{value}' => SKIP")
        next
      end
    elsif type == 'Team List'
      user_name = @a_user_id_to_j_user_name[value]
      if user_name.nil?
        warning("Unknown assembla user='#{value}' for 'Team List' field title='#{k}' => SKIP")
      elsif @inactive_jira_users.include?(user_name)
        warning("Inactive jira user='#{user_name}' for 'Team List' field title='#{k}' => SKIP")
      else
        fields[k.to_sym] = { name: user_name }
      end
    elsif type == 'Date Time'
      # Assembla custom fields of type "Date Time" have format: "YYYY-MM-DD hh:mm:ss" but they need to be
      # converted to ISO date format: "yyyy-MM-dd\'T\'HH:mm:ss.SSSZ".
      if value.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
        value = value.sub(' ', 'T') + '.000Z'
        # value = value.sub(' ', 'T') + '.000' + ASSEMBLA_TIMEZONE
      elsif value.match?(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/)
        # Assembla BUG: seconds are missing, add them!
        value = "#{value}:00"
        value = value.sub(' ', 'T') + '.000Z'
      end
      fields[k] = value
    else
      fields[k] = value
    end
    # puts "#{counter}: type='#{type}', key='#{k}', value='#{value}'"
  end

  case issue_type[:name]
  when 'epic'
    epic_name = (summary =~ /^epic: /i ? summary[6..-1] : summary)
    fields['Epic Name'] = epic_name
  when 'story'
    fields['Story Points'] = story_points.to_i unless story_points == '0'
  when 'sub-task'
    parent_issue = get_parent_issue(ticket)
    unless parent_issue.nil?
      fields[:parent] = { id: parent_issue[:jira_ticket_id] }
    end
  end

  jira_ticket_id = nil
  jira_ticket_key = nil
  message = nil
  ok = false
  retries = 0
  begin
    fields_payload = @customfield_name_to_id.each_with_object(fields.compact) do |(name, id), h|
      h[id.to_sym] = h.delete(name) if h[name] # transform_keys
    end
    payload = { create: {}, fields: fields_payload }
    response = RestClient::Request.execute(method: :post, url: URL_JIRA_ISSUES, payload: payload.to_json, headers: JIRA_HEADERS_ADMIN)
    body = JSON.parse(response.body)
    jira_ticket_id = body['id']
    jira_ticket_key = body['key']
    message = "id='#{jira_ticket_id}' key='#{jira_ticket_key}'"

    # Check for unresolved ticket links that have to be resolved later.
    summary_ticket_links = !/#\d+/.match(summary).nil?
    description_ticket_links = !/#\d+/.match(reformatted_description).nil?
    # puts "summary_ticket_links='#{summary_ticket_links}'" if summary_ticket_links
    # puts "description_ticket_links='#{description_ticket_links}'" if description_ticket_links
    if summary_ticket_links || description_ticket_links
      @jira_ticket_links << {
        jira_ticket_key: jira_ticket_key,
        summary: summary_ticket_links,
        description: description_ticket_links
      }
    end

    ok = true
  rescue RestClient::ExceptionWithResponse => e
    error = JSON.parse(e.response)
    message = "no messages"
    if !error['errors'].empty?
      message = error['errors'].map { |k, v| "#{k}: #{v}" }.join(' | ')
    elsif !error['errorMessages'].empty?
      message = error['errorMessages'].join(' | ')
    end
    retries += 1
    recover = false
    if retries < MAX_RETRY
      error['errors'].each do |err|
        key = err[0]
        reason = err[1]
        case key
        when 'summary'
          case reason
          when /can't exceed 255 characters/
            # Truncate the summary below limit.
            max = 255
            fields[:summary] = "#{fields[:summary][0...max - 3]}..."
            puts "Truncated summary at #{max} characters to '#{fields[:summary]}'"
            recover = true
          end
        when 'assignee'
          case reason
          when /cannot be assigned issues/i
            # fields['Assembla-Assignee'] = fields[:assignee][:name]
            fields[:assignee][:id] = JIRA_API_LEAD_ACCOUNT_ID
            puts "Cannot be assigned issues: #{assignee_name}, changed to JIRA_API_LEAD_ACCOUNT_ID='#{JIRA_API_LEAD_ACCOUNT_ID}'"
            @cannot_be_assigned_issues << assignee_name unless @cannot_be_assigned_issues.include?(assignee_name)
            recover = true
          end
        when 'reporter'
          case reason
          when /cannot be set/i
            fields.delete(:reporter)
            puts "Removed reporter '#{reporter_name}' from issue"
            recover = true
          when /is not a user/i
            fields['Assembla-Reporter'] = fields[:reporter][:name]
            # fields[:reporter][:name] = JIRA_API_UNKNOWN_USER
            fields[:reporter][:id] = JIRA_API_LEAD_ACCOUNT_ID
            puts "Is not a user: #{reporter_name}"
            @is_not_a_user << reporter_name unless @is_not_a_user.include?(reporter_name)
            recover = true
          end
        when 'issuetype'
          case reason
          when /is a sub-task but parent issue key or id not specified/i
            issue_type = {
              id: @issue_type_name_to_id['task'],
              name: 'task'
            }
            fields[:issuetype][:id] = issue_type[:id]
            fields.delete(:parent)
            recover = true
          end
        when 'parent'
          case reason
          when /could not find issue by id or key/i
            fields.delete(:parent)
            recover = true
          end
        when /customfield_/
          key += " (#{@customfield_id_to_name[key]})"
        end
        puts "POST #{URL_JIRA_ISSUES} payload='#{payload.inspect.sub(/:description=>"[^"]+",/, ':description=>"...",')}' => NOK (key='#{key}', reason='#{reason}')" unless recover
      end
    end
    retry if retries < MAX_RETRY && recover
  rescue => e
    message = e.message
  end

  dump_payload = ok ? '' : ' ' + payload.inspect.sub(/:description=>"[^"]+",/, ':description=>"...",')
  percentage = ((counter * 100) / total).round.to_s.rjust(3)
  puts "#{percentage}% [#{counter}|#{total}|#{issue_type[:name].upcase}] POST #{URL_JIRA_ISSUES} #{ticket_number}#{dump_payload} => #{ok ? '' : 'N'}OK (#{message}) retries = #{retries}#{summary_ticket_links || description_ticket_links ? ' (*)' : ''}"

  if ok
    if ticket['description'] != reformatted_description
      @tickets_diffs << {
        assembla_ticket_id: ticket_id,
        assembla_ticket_number: ticket_number,
        jira_ticket_id: jira_ticket_id,
        jira_ticket_key: jira_ticket_key,
        project_id: project_id,
        before: ticket['description'],
        after: reformatted_description
      }
    end
    @assembla_number_to_jira_key[ticket_number] = jira_ticket_key
  end

  {
    result: (ok ? 'OK' : 'NOK'),
    retries: retries,
    message: (ok ? '' : message.gsub(' | ', "\n\n")),
    jira_ticket_id: jira_ticket_id,
    jira_ticket_key: jira_ticket_key,
    project_id: project_id,
    summary: summary,
    issue_type_id: issue_type[:id],
    issue_type_name: issue_type[:name],
    assignee_name: assignee_name,
    reporter_name: reporter_name,
    priority_name: priority_name,
    status_name: status_name,
    labels: (labels || []).join('|'),
    description: description,
    assembla_ticket_id: ticket_id,
    assembla_ticket_number: ticket_number,
    milestone_name: @nr_milestones ? milestone[:name] : '',
    story_rank: story_rank
  }
end

# Ensure that the project exists, otherwise try and create it and if that fails ask the user to create it first.
@project = jira_get_project_by_name(JIRA_API_PROJECT_NAME)
if @project
  puts "Found project '#{JIRA_API_PROJECT_NAME}' id='#{@project['id']}' key='#{@project['key']}'"
else
  @project = jira_create_project(JIRA_API_PROJECT_NAME, JIRA_PROJECT_KEY, JIRA_API_PROJECT_TYPE)
  if @project
    puts "Created project '#{JIRA_API_PROJECT_NAME}' id='#{@project['id']}' key='#{@project['key']}'"
  else
    goodbye("You must first create a Jira project called '#{JIRA_API_PROJECT_NAME}' in order to continue (see README.md)")
  end
end

# --- USERS --- #

puts "\nTotal users: #{@jira_users.length}"
puts '  assemblaId              accountId                 name/key'
puts '  ----------              ---------                 --------'
@jira_users.each do |user|
  puts "* #{user['assemblaid']}  #{user['accountid']}  #{user['name']}"
end

# Make sure that the unknown user exists and is active, otherwise try and create
puts "\nUnknown user:"
# IMPORTANT: You might have to comment out the following if-statement to get things working.
if JIRA_API_UNKNOWN_USER && JIRA_API_UNKNOWN_USER.length
  # user = jira_get_user(JIRA_API_UNKNOWN_USER, false)
  user = jira_get_user(JIRA_API_LEAD_ACCOUNT_ID, false)
  if user
    goodbye("Please activate Jira unknown user '#{JIRA_API_UNKNOWN_USER}' (see README.md)") unless user['active']
    puts "Found Jira unknown user '#{JIRA_API_UNKNOWN_USER}' => OK"
  else
    user = {}
    user[:assemblaName] = JIRA_API_UNKNOWN_USER
    user[:emailAddress] = "#{JIRA_API_UNKNOWN_USER}@#{JIRA_API_DEFAULT_EMAIL}"
    user[:assemblaLogin] = JIRA_API_UNKNOWN_USER
    result = jira_create_user(user)
    goodbye("Cannot find Jira unknown user '#{JIRA_API_UNKNOWN_USER}', make sure that has been created and enabled (see README.md).") unless result
    puts "Created Jira unknown user '#{JIRA_API_UNKNOWN_USER}'"
  end
else
  goodbye("Please define 'JIRA_API_UNKNOWN_USER' in the .env file (see README.md)")
end

# --- MILESTONES --- #

puts "\nTotal milestones: #{@milestones_assembla.length}"

@milestone_id_to_name = {}
@milestones_assembla.each do |milestone|
  @milestone_id_to_name[milestone['id']] = milestone['title']
end

@milestone_id_to_name.each do |k, v|
  puts "* #{k} #{v}"
end

# --- ISSUE TYPES --- #

# IMPORTANT: the sub-tasks MUST be done last in order to be able to be associated with the parent tasks/stories.
@issue_types = %w(epic story task bug sub-task)

puts "\nTotal issue types: #{@issue_types_jira.length}"

@issue_type_name_to_id = {}
@issue_types_jira.each do |type|
  @issue_type_name_to_id[type['name'].downcase] = type['id']
end

@issue_type_name_to_id.each do |k, v|
  puts "* #{v} #{k}"
end

# Make sure that all issue types are indeed available.
@missing_issue_types = []
@issue_types.each do |issue_type|
  @missing_issue_types << issue_type unless @issue_type_name_to_id[issue_type]
end

if @missing_issue_types.length.positive?
  goodbye("Missing issue types: #{@missing_issue_types.join(',')}, please create (see README.md) and re-run jira_get_info script.")
end

# --- PRIORITIES --- #

puts "\nPriorities:"

@priority_id_to_name = {}
@priorities_jira = jira_get_priorities
if @priorities_jira
  @priorities_jira.each do |priority|
    @priority_id_to_name[priority['id']] = priority['name']
  end
else
  goodbye('Cannot get priorities!')
end

@priority_id_to_name.each do |k, v|
  puts "#{k} #{v}"
end

# --- JIRA fields --- #

puts "\nJira fields:"

@fields_jira = jira_get_fields
goodbye('Cannot get fields!') unless @fields_jira

@fields_jira.sort_by { |k| k['id'] }.each do |field|
  puts "#{field['id']} '#{field['name']}'" unless field['custom']
end

# --- JIRA custom fields --- #

puts "\nJira custom fields:"

@fields_jira.sort_by { |k| k['id'] }.each do |field|
  puts "#{field['id']} '#{field['name']}'" if field['custom'] && field['name'] !~ /Assembla/
end

# --- JIRA custom Assembla fields --- #

puts "\nJira custom Assembla fields:"

@fields_jira.sort_by { |k| k['id'] }.each do |field|
  puts "#{field['id']} '#{field['name']}'" if field['custom'] && field['name'] =~ /Assembla/
end

@all_custom_field_names = CUSTOM_FIELD_NAMES.dup
@custom_fields_assembla.map { |field| field['title'] }.each do |name|
  @all_custom_field_names << name
end

@customfield_name_to_id = {}
@customfield_id_to_name = {}

missing_fields = []
@all_custom_field_names.each do |name|
  field = jira_get_field_by_name(name)
  if field
    id = field['id']
    @customfield_name_to_id[name] = id
    @customfield_id_to_name[id] = name
  else
    missing_fields << name
  end
end

unless missing_fields.length.zero?
  nok = []
  missing_fields.each do |name|
    description = "Custom field '#{name}'"
    custom_field = jira_create_custom_field(name, description,
                                            'com.atlassian.jira.plugin.system.customfieldtypes:readonlyfield',
                                            'com.atlassian.jira.plugin.system.customfieldtypes:textsearcher')
    unless custom_field
      nok << name
    end
  end
  len = nok.length
  unless len.zero?
    goodbye("Custom field#{len == 1 ? '' : 's'} '#{nok.join('\',\'')}' #{len == 1 ? 'is' : 'are'} missing, please define in Jira and make sure to attach it to the appropriate screens (see README.md)")
  end
end

# --- Import all Assembla tickets into Jira --- #

@total_tickets = @tickets_assembla.length

# IMPORTANT: Make sure that the tickets are ordered chronologically from first (oldest) to last (newest)
@tickets_assembla.sort! { |x, y| x['created_on'] <=> y['created_on'] }

@jira_issues = []
@jira_ticket_links = []

@tickets_diffs = []

# Some sanity checks just in case
@invalid_reporters = []
@tickets_assembla.each do |ticket|
  ticket_id = ticket['id']
  reporter_id = ticket['reporter_id']
  jira_name = @a_user_id_to_j_user_name[reporter_id]
  unless jira_name
    @invalid_reporters << {
      ticket_id: ticket_id,
      reporter_id: reporter_id
    }
  end
end

if @invalid_reporters.length.positive?
  puts "\nInvalid reporters: #{@invalid_reporters.length}"
  @invalid_reporters.each do |reporter|
    puts "ticket_id='#{reporter[:ticket_id]}' reporter: id='#{reporter[:reporter_id]}'"
  end
  # goodbye('Please fix before continuing')
end

puts "\nReporters => OK"

# We append a running total in case a restart from a given offset is done.
@tickets_jira_csv_append = "#{OUTPUT_DIR_JIRA}/jira-tickets-append.csv"

@completed = 0
@skip_remaining = true
puts "SKIP to ticket #{@startAt}" if @startAt > 1
@tickets_assembla.each_with_index do |ticket, index|
  counter = index + 1
  next if @startAt > counter
  if @maxResults != -1 && @completed > @maxResults - 1
    puts "SKIP remaining #{@tickets_assembla.length - (@startAt - 1 + @maxResults)} tickets" if @skip_remaining
    @skip_remaining = false
    next
  end

  issue = create_ticket_jira(ticket, counter, @total_tickets)
  write_csv_file_append(@tickets_jira_csv_append, [issue], counter == 1)
  @jira_issues << issue

  @completed = @completed + 1
end

puts "Total tickets: #{@total_tickets}"
tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets.csv"
write_csv_file(tickets_jira_csv, @jira_issues)

puts "\nTotal unresolved ticket links: #{@jira_ticket_links.length}"
puts "[#{@jira_ticket_links.map { |rec| rec[:jira_ticket_key] }.join(',')}]" if @jira_ticket_links.length.nonzero?
ticket_links_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-ticket-links.csv"
write_csv_file(ticket_links_jira_csv, @jira_ticket_links)

tickets_diffs_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets-diffs.csv"
write_csv_file(tickets_diffs_jira_csv, @tickets_diffs)

# Statistics
#
tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets.csv"
@jira_tickets = csv_to_array(tickets_jira_csv)

puts

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

if total.zero?
  puts 'Congratulations! All tickets were imported successfully.'
else
  puts 'Oops! Not all tickets were imported successfully.'
  puts "Total NOK: #{total}"
  h.each do |key, value|
    puts "#{value}: '#{key}'"
  end
end
