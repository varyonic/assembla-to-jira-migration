# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-assembla.rb'

@assembla_status_to_jira = {}
JIRA_API_STATUSES.split(',').each do |status|
  if status.index(':')
    m = /^(.*):(.*)$/.match(status)
    from = m[1]
    to = m[2]
    @assembla_status_to_jira[from] = to
  else
    @assembla_status_to_jira[status] = status
  end
  @jira_initial_status ||= to
end

puts "\nAssembla status => Jira status"
@assembla_status_to_jira.keys.each do |key|
  puts "* #{key} => #{@assembla_status_to_jira[key]}"
end

def jira_get_status_from_assembla(assembla_status)
  jira_status = @assembla_status_to_jira[assembla_status]
  goodbye("Cannot find jira_status from assembla_status='#{assembla_status}'") unless jira_status
  jira_status
end

# Assembla tickets
tickets_csv = "#{OUTPUT_DIR_ASSEMBLA}/tickets.csv"
@tickets_assembla = csv_to_array(tickets_csv)

# --- Filter by date if TICKET_CREATED_ON is defined --- #
tickets_created_on = get_tickets_created_on

if tickets_created_on
  puts "\nFilter newer than: #{tickets_created_on}"
  @tickets_assembla.select! { |item| item_newer_than?(item, tickets_created_on) }
end

# Collect ticket statuses
@assembla_statuses = {}
@extra_summary_types = {}
@tickets_assembla.each do |ticket|
  status = ticket['status']
  summary = ticket['summary']
  if @assembla_statuses[status].nil?
    @assembla_statuses[status] = 0
  else
    @assembla_statuses[status] += 1
  end
  if summary.match?(/^([A-Z]*):/)
    t = summary.sub(/:.*$/, '\1')
    @extra_summary_types[t] = true if !ASSEMBLA_TYPES_EXTRA.include?(t) && @extra_summary_types[t].nil?
  end
end

@total_assembla_tickets = @tickets_assembla.length
puts "\nTotal Assembla tickets: #{@total_assembla_tickets}"

puts "\nAssembla ticket statuses:"
@assembla_statuses.keys.each do |key|
  puts "* #{key} => #{@assembla_statuses[key]}"
end

if @extra_summary_types.length.positive?
  puts "\nExtra (possible) statuses detected in the summary (ignored): #{@extra_summary_types.length}"
  @extra_summary_types.keys.sort.each do |type|
    puts "* #{type}"
  end
end

# Sanity check just in case
@missing_statuses = []
@assembla_statuses.keys.each do |key|
  @missing_statuses << key unless @assembla_status_to_jira[key]
end

if @missing_statuses.length.positive?
  puts "\nSanity check => NOK"
  puts 'The following statuses are missing:'
  @missing_statuses.each do |status|
    puts "* #{status}"
  end
  goodbye('Update JIRA_API_STATUSES in .env file and create JIRA statuses if needed')
end

puts
puts 'Sanity check => OK'

# Jira tickets
resolutions_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-resolutions.csv"
statuses_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-statuses.csv"
tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets.csv"

@resolutions_jira = csv_to_array(resolutions_jira_csv)
@statuses_jira = csv_to_array(statuses_jira_csv)
@tickets_jira = csv_to_array(tickets_jira_csv).select { |ticket| ticket['result'] == 'OK' }

@jira_resolution_name_to_id = {}
puts "\nJira ticket resolutions:"
@resolutions_jira.each do |resolution|
  @jira_resolution_name_to_id[resolution['name']] = resolution['id']
  puts "* id='#{resolution['id']}' name='#{resolution['name']}'"
end

@jira_status_name_to_id = {}
puts "\nJira ticket statuses:"
@statuses_jira.each do |status|
  @jira_status_name_to_id[status['name']] = status['id']
  puts "* id='#{status['id']}' name='#{status['name']}'"
end

def jira_get_status_id(name)
  id = @jira_status_name_to_id[name]
  goodbye("Cannot get status id from name='#{name}'") unless id
  id
end

# Convert assembla_ticket_id to jira_ticket
@assembla_id_to_jira = {}
@jira_id_to_login = {}
@tickets_jira.each do |ticket|
  jira_id = ticket['jira_ticket_id']
  assembla_id = ticket['assembla_ticket_id']
  @assembla_id_to_jira[assembla_id] = jira_id
  @jira_id_to_login[jira_id] = ticket['reporter_name']
end

# GET /rest/api/2/issue/{issueIdOrKey}/transitions
def jira_get_transitions(issue_id)
  result = nil
  user_login = @jira_id_to_login[issue_id]
  user_login.sub!(/@.*$/, '')
  # user_email = @user_login_to_email[user_login]
  # headers = headers_user_login(user_login, user_email)
  headers = JIRA_HEADERS_ADMIN
  url = "#{URL_JIRA_ISSUES}/#{issue_id}/transitions"
  begin
    response = RestClient::Request.execute(method: :get, url: url, headers: headers)
    result = JSON.parse(response.body)
    puts "\nGET #{url} => OK"
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'GET', url)
  rescue RestClient::Exception => e
    rest_client_exception(e, 'GET', url)
  rescue => e
    puts "\nGET #{url} => NOK (#{e.message})"
  end
  if result.nil?
    nil
  else
    transitions = result['transitions']
    puts "\nJira ticket transitions:"
    transitions.each do |transition|
      puts "* #{transition['id']} '#{transition['name']}' =>  #{transition['to']['id']} '#{transition['to']['name']}'"
    end
    puts
    transitions
  end
end

# POST /rest/api/2/issue/{issueIdOrKey}/transitions
def jira_update_status(issue_id, assembla_status, counter)
  if assembla_status.casecmp('Done').zero? || assembla_status.casecmp('invalid').zero?
    payload = {
      update: {},
      transition: {
        id: jira_get_transition_target_id('Done')
      }
    }.to_json
    transition = {
      from: {
        id: jira_get_status_id(@jira_initial_status),
        name: @jira_initial_status
      },
      to: {
        id: jira_get_status_id('Done'),
        name: 'Done'
      }
    }
  elsif assembla_status.casecmp('new').zero?
    # Do nothing
    transition = {
      from: {
        id: jira_get_status_id(@jira_initial_status),
        name: @jira_initial_status
      },
      to: {
        id: jira_get_status_id(@jira_initial_status),
        name: @jira_initial_status
      }
    }
    return { transition: transition }
  elsif assembla_status.casecmp('In Progress').zero?
    payload = {
      update: {},
      transition: {
        id: jira_get_transition_target_id('In Progress')
      }
    }.to_json
    transition = {
      from: {
        id: jira_get_status_id(@jira_initial_status),
        name: @jira_initial_status
      },
      to: {
        id: jira_get_status_id('In Progress'),
        name: 'In Progress'
      }
    }
  else
    # Handle other statuses
    jira_status = jira_get_status_from_assembla(assembla_status)
    payload = {
      update: {},
      transition: {
        id: jira_get_transition_target_id(jira_status)
      }
    }.to_json
    transition = {
      from: {
        id: jira_get_status_id(@jira_initial_status),
        name: @jira_initial_status
      },
      to: {
        id: jira_get_status_id(jira_status),
        name: jira_status
      }
    }
  end

  result = nil
  user_login = @jira_id_to_login[issue_id]
  user_login.sub!(/@.*$/, '')
  # user_email = @user_login_to_email[user_login]
  # headers = headers_user_login(user_login, user_email)
  headers = JIRA_HEADERS_ADMIN
  url = "#{URL_JIRA_ISSUES}/#{issue_id}/transitions"

  percentage = ((counter * 100) / @total_assembla_tickets).round.to_s.rjust(3)
  # By default all created issues start with a status of @jira_initial_status, so if the transition
  # is to @jira_initial_status we just skip it.
  #
  if transition[:to][:name].casecmp(@jira_initial_status).zero?
    puts "#{percentage}% [#{counter}|#{@total_assembla_tickets}] transition '#{@jira_initial_status}' => SKIP"
    return { transition: transition }
  end

  begin
    RestClient::Request.execute(method: :post, url: url, payload: payload, headers: headers)
    puts "#{percentage}% [#{counter}|#{@total_assembla_tickets}] POST #{url} '#{transition[:from][:name]}' to '#{transition[:to][:name]}' => OK"
    result = { transition: transition }
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'POST', url, payload)
  rescue => e
    puts "#{percentage}% [#{counter}|#{@total_assembla_tickets}] POST #{url} #{payload.inspect} => NOK (#{e.message})"
  end
  if result
    # If the issue has been closed (Done) we set the resolution to the appropriate value
    if assembla_status.casecmp('Done').zero? || assembla_status.casecmp('invalid').zero?
      resolution_name = assembla_status.casecmp('invalid').zero? ? "Won't do" : 'Done'
      resolution_id = @jira_resolution_name_to_id[resolution_name].to_i
      unless resolution_id == '0'
        payload = {
          update: {},
          fields: {
            resolution: {
              id: "#{resolution_id}"
            }
          }
        }.to_json
        url = "#{URL_JIRA_ISSUES}/#{issue_id}?notifyUsers=false"
        begin
          RestClient::Request.execute(method: :put, url: url, payload: payload, headers: headers)
        rescue RestClient::ExceptionWithResponse => e
          rest_client_exception(e, 'PUT', url, payload)
        rescue => e
          puts "PUT #{url} resolution='#{resolution_name}' => NOK (#{e.message})"
        end
      end
    end
  end
  result
end

first_id = @tickets_assembla.first['id']
goodbye('Cannot find first_id') unless first_id

issue_id = @assembla_id_to_jira[first_id]
goodbye("Cannot find issue_id, first_id='#{first_id}'") unless issue_id

@transitions = jira_get_transitions(issue_id)
goodbye("No transitions available, first_id='#{first_id}', issue_id=#{issue_id}") unless @transitions && @transitions

@transition_target_name_to_id = {}
@transitions.each do |transition|
  @transition_target_name_to_id[transition['to']['name']] = transition['id'].to_i
end

def jira_get_transition_target_id(name)
  id = @transition_target_name_to_id[name]
  goodbye("Cannot get transition target id from name='#{name}'") unless id
  id
end

@jira_updates_tickets = []

@tickets_assembla.each_with_index do |ticket, index|
  assembla_ticket_id = ticket['id']
  assembla_ticket_status = ticket['status']
  jira_ticket_id = @assembla_id_to_jira[ticket['id']]
  unless jira_ticket_id
    warning("Cannot find jira_ticket_id for assembla_ticket_id='#{assembla_ticket_id}'")
    next
  end
  result = jira_update_status(jira_ticket_id, assembla_ticket_status, index + 1)
  @jira_updates_tickets << {
    result: result.nil? ? 'NOK' : 'OK',
    assembla_ticket_id: assembla_ticket_id,
    assembla_ticket_status: assembla_ticket_status,
    jira_ticket_id: jira_ticket_id,
    jira_transition_from_id: result.nil? ? 0 : result[:transition][:from][:id],
    jira_transition_from_name: result.nil? ? 0 : result[:transition][:from][:name],
    jira_transition_to_id: result.nil? ? 0 : result[:transition][:to][:id],
    jira_transition_to_name: result.nil? ? 0 : result[:transition][:to][:name]
  }
end

puts "\nTotal updates: #{@jira_updates_tickets.length}"
updates_tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets-status-updates.csv"
write_csv_file(updates_tickets_jira_csv, @jira_updates_tickets)
