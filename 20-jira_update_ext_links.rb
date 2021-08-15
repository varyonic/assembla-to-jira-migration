# frozen_string_literal: true

load './lib/common.rb'

# Set to true if you just want to run and verify this script without actually updating any external links.
@dry_run = true

# You can also pass a parameter 'dry_run=true|false'
if ARGV.length == 1
  goodbye("Invalid ARGV0='#{ARGV[0]}', must be 'dry_run=true|false'") unless /^dry_run=(true|false)$/i.match?(ARGV[0])
  @dry_run = ARGV[0].split('=')[1].casecmp('true') == 0
  puts "Detected ARGV0='#{ARGV[0]}' => #{@dry_run}"
end

if @dry_run
  puts
  puts '----------------'
  puts 'DRY RUN enabled!'
  puts '----------------'
  puts
end

DELIMITER = '|||'

@bitbucket_conversions = {}
@bitbucket_from_to_name = {}
@bitbucket_from_to_url = {}

def assembla_to_bitbucket_repo_url(assembla_repo_url, assembla_space_key)
  bitbucket_repo_url = nil
  found_conversion = @bitbucket_conversions.detect { |key, _| key.split(DELIMITER)[0] == assembla_space_key }[1]
  if found_conversion
    found_value = found_conversion.detect { |item| item[:assembla_repo_url] == assembla_repo_url }
    if found_value
      bitbucket_repo_url = found_value[:bitbucket_repo_url]
    end
  end
  bitbucket_repo_url
end

if BITBUCKET_REPO_URL
  puts "BITBUCKET_REPO_URL='#{BITBUCKET_REPO_URL}'"
else
  puts 'Warning: BITBUCKET_REPO_URL is NOT defined'
end

if File.exist?(BITBUCKET_REPO_CONVERSIONS)

  puts "Found file '#{BITBUCKET_REPO_CONVERSIONS}'"

  column_names = %w{
    assembla_space_key
    assembla_space_name
    assembla_repo_name
    bitbucket_repo_name
    bitbucket_repo_url
    assembla_repo_url
  }

  @assembla_space_keys = []
  @assembla_space_names = []
  @assembla_repo_names = []
  @assembla_repo_urls = []
  @bitbucket_repo_names = []
  @bitbucket_repo_urls = []

  # assembla_space_ey,assembla_space_name,assembla_repo_name,bitbucket_repo_name,bitbucket_repo_url,assembla_repo_url
  repos = csv_to_array(BITBUCKET_REPO_CONVERSIONS)

  if repos.count.zero?
    puts 'There are no entries found => Exit'
    exit
  end

  # Make sure that all of the columns are present.
  repo_first = repos.first
  missing_column_names = []
  column_names.each do |column_name|
    missing_column_names << column_name if repo_first[column_name].nil?
  end

  unless missing_column_names.count.zero?
    puts 'The following columns are missing:'
    missing_column_names.each do |missing_column_name|
      puts "* #{missing_column_name}"
    end
    puts ' => Exit'
    exit
  end

  repos.each do |repo|
    assembla_space_key = repo['assembla_space_key']
    assembla_space_name = repo['assembla_space_name']
    assembla_repo_name = repo['assembla_repo_name']
    assembla_repo_url = repo['assembla_repo_url']
    bitbucket_repo_name = repo['bitbucket_repo_name']
    bitbucket_repo_url = repo['bitbucket_repo_url']

    @assembla_space_keys << assembla_space_key unless @assembla_space_keys.include?(assembla_space_key)
    @assembla_space_names << assembla_space_name unless @assembla_space_names.include?(assembla_space_name)
    @assembla_repo_names << assembla_repo_name unless @assembla_repo_names.include?(assembla_repo_name)
    @assembla_repo_urls << assembla_repo_url unless @assembla_repo_urls.include?(assembla_repo_url)
    @bitbucket_repo_names << bitbucket_repo_name unless @bitbucket_repo_names.include?(bitbucket_repo_name)
    @bitbucket_repo_urls << bitbucket_repo_url unless @bitbucket_repo_urls.include?(bitbucket_repo_url)

    conversions_key = "#{assembla_space_key}#{DELIMITER}#{assembla_space_name}"
    @bitbucket_conversions[conversions_key] ||= []
    @bitbucket_conversions[conversions_key] << {
      assembla_repo_name: assembla_repo_name,
      assembla_repo_url: assembla_repo_url,
      bitbucket_repo_name: bitbucket_repo_name,
      bitbucket_repo_url: bitbucket_repo_url
    }

    if @bitbucket_from_to_name[assembla_repo_name] && @bitbucket_from_to_name[assembla_repo_name] != bitbucket_repo_name
      goodbye("bitbucket_repo_name='#{bitbucket_repo_name}' @from_to_name[#{assembla_repo_name}] = '#{@bitbucket_from_to_name[assembla_repo_name]}' is already set")
    else
      @bitbucket_from_to_name[assembla_repo_name] = bitbucket_repo_name
    end

    if @bitbucket_from_to_url[assembla_repo_url] && @bitbucket_from_to_url[assembla_repo_url] != bitbucket_repo_url
      goodbye("bitbucket_repo_url='#{bitbucket_repo_url}' @from_to_url[#{assembla_repo_url}] = '#{@bitbucket_from_to_url[assembla_repo_url]}' is already set")
    else
      @bitbucket_from_to_url[assembla_repo_url] = bitbucket_repo_url
    end
  end

  # Sanity checks, just in case (you never know)
  repos.each do |repo|
    assembla_space_key = repo['assembla_space_key']
    assembla_repo_url = repo['assembla_repo_url']
    bitbucket_repo_url = repo['bitbucket_repo_url']
    unless bitbucket_repo_url == assembla_to_bitbucket_repo_url(assembla_repo_url, assembla_space_key)
      puts "Cannot find correct bitbucket_repo_url='#{bitbucket_repo_url}' for assembla_space_key='#{assembla_space_key}' assembla_repo_url='#{assembla_repo_url}'"
      exit
    end
  end

  puts "All sanity checks pass"
else
  puts "File BITBUCKET_REPO_CONVERSION='#{BITBUCKET_REPO_CONVERSIONS}' doesn't exist"
end

@assembla_spaces = csv_to_array("#{OUTPUT_DIR_ASSEMBLA}/spaces.csv")
@a_space_id_to_wiki_name = {}
puts "\nTotal assembla spaces: #{@assembla_spaces.count}"
@assembla_spaces.each do |space|
  id = space['id']
  name = space['name']
  wiki_name = space['wiki_name']
  @a_space_id_to_wiki_name[id] = wiki_name
  puts "* id='#{id}' name='#{name}' wiki_name='#{wiki_name}'"
end
puts

@all_projects = jira_get_projects

@projects = []

puts "\nJIRA_API_SPACE_TO_PROJECT='#{JIRA_API_SPACE_TO_PROJECT}'"
JIRA_API_SPACE_TO_PROJECT.split(',').each do |item|
  space, key = item.split(':')

  goodbye("Missing space, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless space
  goodbye("Missing key, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless key

  project = @all_projects.detect { |p| p['key'] == key }
  goodbye("Cannot find project with key=#{key}, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless project
  project_name = project['name']

  tickets = csv_to_array("#{OUTPUT_DIR_JIRA}/jira-tickets.csv").select { |ticket| ticket['result'] == 'OK' }
  comments = csv_to_array("#{OUTPUT_DIR_JIRA}/jira-comments.csv")

  ticket_a_nr_to_j_key = {}
  tickets.each do |ticket|
    ticket_a_nr_to_j_key[ticket['assembla_ticket_number']] = ticket['jira_ticket_key']
  end

  comment_a_id_to_j_id = {}
  comments.each do |comment|
    comment_a_id_to_j_id[comment['assembla_comment_id']] = comment['jira_comment_id']
  end

  puts "* space='#{space}' key='#{key}' project_name='#{project_name}' | tickets: #{tickets.count} | comments: #{comments.count}"

  @projects << {
    space: space,
    key: key,
    name: project_name,
    output_dir: OUTPUT_DIR_JIRA,
    ticket_a_nr_to_j_key: ticket_a_nr_to_j_key,
    comment_a_id_to_j_id: comment_a_id_to_j_id
  }
end
puts

@project_by_space = {}
@projects.each do |project|
  @project_by_space[project[:space]] = project
end

@tickets_jira = csv_to_array("#{OUTPUT_DIR_JIRA}/jira-tickets.csv").select { |ticket| ticket['result'] == 'OK' }

@ticket_a_id_to_a_nr = {}
@ticket_a_nr_to_j_key = {}
@ticket_j_key_to_j_reporter = {}
@tickets_jira.each do |ticket|
  @ticket_a_id_to_a_nr[ticket['assembla_ticket_id']] = ticket['assembla_ticket_number']
  @ticket_a_nr_to_j_key[ticket['assembla_ticket_number']] = ticket['jira_ticket_key']
  @ticket_j_key_to_j_reporter[ticket['jira_ticket_key']] = ticket['reporter_name']
end

@comments_jira = csv_to_array("#{OUTPUT_DIR_JIRA}/jira-comments.csv")

@comment_j_key_to_j_login = {}
@comments_jira.each do |comment|
  @comment_j_key_to_j_login[comment['jira_ticket_key']] = comment['user_login']
end

def jira_update_issue_description(issue_key, description)
  result = nil
  user_login = @ticket_j_key_to_j_reporter[issue_key]
  user_login.sub!(/@.*$/, '')
  headers = JIRA_HEADERS_ADMIN
  url = "#{URL_JIRA_ISSUES}/#{issue_key}?notifyUsers=false"
  payload = {
    update: {},
    fields: {
      description: description
    }
  }.to_json
  begin
    RestClient::Request.execute(method: :put, url: url, payload: payload, headers: headers)
    puts "PUT #{url} description => OK"
    result = true
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'PUT', url, payload)
  rescue => e
    puts "PUT #{url} description => NOK (#{e.message})"
  end
  result
end

def jira_update_comment_body(issue_key, comment_id, body)
  result = nil
  user_login = @comment_j_key_to_j_login[issue_key]
  user_login.sub!(/@.*$/, '')
  headers = JIRA_HEADERS_ADMIN
  url = "#{URL_JIRA_ISSUES}/#{issue_key}/comment/#{comment_id}"
  payload = {
    body: body
  }.to_json
  begin
    RestClient::Request.execute(method: :put, url: url, payload: payload, headers: headers)
    puts "PUT #{url} body => OK"
    result = true
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'PUT', url, payload)
  rescue => e
    puts "PUT #{url} description => NOK (#{e.message})"
  end
  result
end

@missing_issue_keys = {}

# Convert the Assembla ticket number to the Jira issue key
def link_ticket_a_nr_to_j_key(space, assembla_ticket_nr)
  project = get_project_by_space(space)
  goodbye("Cannot get project, space='#{space}'") unless project
  jira_issue_key = project[:ticket_a_nr_to_j_key][assembla_ticket_nr]
  unless jira_issue_key
    @missing_issue_keys[space] = {} unless @missing_issue_keys[space]
    @missing_issue_keys[space][assembla_ticket_nr] = 0 unless @missing_issue_keys[space][assembla_ticket_nr]
    @missing_issue_keys[space][assembla_ticket_nr] += 1
    jira_issue_key = '0'
  end
  jira_issue_key
end

@missing_comment_ids = {}

# Convert the Assembla comment id to the Jira comment id
def link_comment_a_id_to_j_id(space, assembla_comment_id)
  return nil unless assembla_comment_id
  project = get_project_by_space(space)
  goodbye("Cannot get project, space='#{space}'") unless project
  jira_comment_id = project[:comment_a_id_to_j_id][assembla_comment_id]
  unless jira_comment_id
    @missing_comment_ids[space] = {} unless @missing_comment_ids[space]
    @missing_comment_ids[space][assembla_comment_id] = 0 unless @missing_comment_ids[space][assembla_comment_id]
    @missing_comment_ids[space][assembla_comment_id] += 1
    jira_comment_id = '0'
  end
  jira_comment_id
end

@converted_spaces = {}

def get_project_by_space(space)
  project = @project_by_space[space]
  if project.nil?
    # It's possible that in the link rather than using the 'space name', it uses the 'space id' instead, adapt to this
    # situation also.
    converted_space = @converted_spaces[space]
    if converted_space
      project = @project_by_space[converted_space]
    else
      wiki_name = @a_space_id_to_wiki_name[space]
      if wiki_name
        @converted_spaces[space] = wiki_name
        puts "get_project_by_space() id='#{space}' converted to wiki_name='#{wiki_name}'"
        project = @project_by_space[wiki_name]
      else
        puts "Cannot find project for space='#{space}' => SKIP"
      end
    end
  end
  project
end

# Tickets:
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary/details#?
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary/details\?tab=activity
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary/activity/ticket:
@re_ticket = %r{https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)(?:-[^)\]]+)?(?:\?.*\b)?}

# => /browse/[:jira-ticket-key]

# Comments:
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)/details?comment=(\d+)
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary?comment=(\d+)
# https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+)-summary?comment=(\d+)#comment:(\d+)
@re_comment = %r{https?://.*?\.assembla\.com/spaces/(.*?)/tickets/(\d+).*?\?comment=(\d+)(?:#comment:\d+)?}

# => /browse/[:jira-ticket-key]?focusedCommentId=[:jira-comment-id]

# TODO: Commits are not supported yet.
# https?://.*?\.assembla\.com/spaces/(.*?)/git/commits/[:hash]
@re_commit = %r{https?://.*?\.assembla\.com/spaces/(.*?)/git/commits/([a-z0-9]+)}

# => https://bitbucket.org/[:company-name]/[[REPO-NAME]]/commits/[:commit_hash]'

@list_external_all = []
@list_external_updated = []
@spaces = {}

@cannot_find_commit_url = {}

def handle_match_commit(match, type, item, line, assembla_ticket_nr, jira_ticket_key, assembla_repo_url, hash)
  puts "handle_match_commit() match='#{match}' type='#{type}' line='#{line}' assembla_ticket_nr='#{assembla_ticket_nr}' jira_ticket_key='#{jira_ticket_key}' assembla_repo_url='#{assembla_repo_url}' hash='#{hash}'"
  replace_with = match
  if BITBUCKET_REPO_URL
    to = @bitbucket_from_to_url[assembla_repo_url]
    if to
      replace_with = "#{BITBUCKET_REPO_URL.sub('[[REPO-NAME]]', to)}/#{hash}"
    else
      unless @cannot_find_commit_url[assembla_repo_url]
        puts "Cannot find a bitbucket url for assembla_repo_url='#{assembla_repo_url}' => SKIP"
        @cannot_find_commit_url[assembla_repo_url] = 1
      end
      @cannot_find_commit_url[assembla_repo_url] += 1
    end
  else
    puts 'BITBUCKET_REPO_URL is not defined => SKIP'
  end
  replace_with
end

def handle_match(match, type, item, line, assembla_ticket_nr, jira_ticket_key, space, assembla_link_ticket_nr, assembla_link_comment_id)
  # jira_link_ticket_key => calculated from link_ticket_a_nr_to_j_key(assembla_link_ticket_nr)
  # jira_link_comment_id => calculated from link_comment_a_id_to_j_id(assembla_link_comment_id)

  replace_with = nil

  @project = get_project_by_space(space)

  # IMPORTANT: Make sure that converted space is used here.
  if @project
    space = @project[:space]

    @spaces[space] = 0 unless @spaces[space]
    @spaces[space] += 1
  end

  is_link_comment = !assembla_link_comment_id.nil?

  assembla_comment_id = type == 'comment' ? item['assembla_comment_id'] : ''
  jira_comment_id = type == 'comment' ? item['jira_comment_id'] : ''
  jira_link_ticket_key = ''
  assembla_link_comment_id ||= ''
  jira_link_comment_id = ''

  # TICKET:  jira_ticket_id,jira_ticket_key,assembla_ticket_id,assembla_ticket_number
  # COMMENT: jira_comment_id,jira_ticket_id,jira_ticket_key,assembla_comment_id,assembla_ticket_id

  # type                         TICKET                 COMMENT
  #                              ======                 =======
  # is_link_comment(True/False)  F(ticket)  T(comment)  F(ticket) T(comment)
  #                              ---------  ----------  --------- ----------
  # assembla_ticket_nr           x          x           x         x
  # jira_ticket_key              x          x           x         x
  # assembla_link_ticket_nr      x          x           x         x
  # jira_link_ticket_key         x          x           x         x (calculated)
  #
  # assembla_comment_id          o          o           x         x
  # jira_comment_id              o          o           x         x
  # assembla_link_comment_id     o          x           o         x
  # jira_link_comment_id         o          x           o         x (calculated)

  if @project
    jira_link_ticket_key = link_ticket_a_nr_to_j_key(space, assembla_link_ticket_nr)
    url = JIRA_API_BROWSE_ISSUE.sub('[:jira-ticket-key]', jira_link_ticket_key)
    if is_link_comment
      jira_link_comment_id = link_comment_a_id_to_j_id(space, assembla_link_comment_id)
      if jira_link_comment_id.to_i.positive?
        url = JIRA_API_BROWSE_COMMENT.sub('[:jira-ticket-key]', jira_link_ticket_key).sub('[:jira-comment-id]', jira_link_comment_id)
      end
    end
    replace_with = "#{JIRA_API_BASE}/#{url}"
  end

  line_after = replace_with.nil? ? '' : line.sub(match, replace_with)

  @list_external_all << {
    result: @project ? 'OK' : 'SKIP',
    replace: replace_with.nil? ? 'NO' : 'YES',
    space: space,
    type: type,
    is_link_comment: is_link_comment,
    assembla_ticket_nr: assembla_ticket_nr,
    jira_ticket_key: jira_ticket_key,
    assembla_comment_id: assembla_comment_id,
    jira_comment_id: jira_comment_id,
    assembla_link_ticket_nr: assembla_link_ticket_nr,
    jira_link_ticket_key: jira_link_ticket_key,
    assembla_link_comment_id: assembla_link_comment_id,
    jira_link_comment_id: jira_link_comment_id,
    match: match,
    replace_with: replace_with.nil? ? '' : replace_with,
    line_before: line,
    line_after: line_after
  }

  replace_with.nil? ? match : replace_with
end

def collect_list_external_all(type, item)
  goodbye("Collect list_external_all: invalid type=#{type}, must be 'ticket' or 'comment'") unless %w(ticket comment).include?(type)

  if type == 'ticket'
    content = item['description']
    assembla_ticket_nr = item['assembla_ticket_number']
    jira_ticket_key = item['jira_ticket_key']
    assembla_comment_id = ''
    jira_comment_id = ''
  else
    content = item['body']
    assembla_ticket_nr = @ticket_a_id_to_a_nr[item['assembla_ticket_id']]
    jira_ticket_key = item['jira_ticket_key']
    assembla_comment_id = item['assembla_comment_id']
    jira_comment_id = item['jira_comment_id']
  end

  # Split content into lines, and ignore the first line.
  lines = split_into_lines(content)
  first_line = lines.shift
  lines_before = lines
  lines_after = []
  lines_changed = false
  lines.each_with_index do |line, index|
    line_before = line
    line_after = line
    if line.strip.length.positive?
      blk = ->(match) { handle_match(match, type, item, line, assembla_ticket_nr, jira_ticket_key, $1, $2, $3) }
      blk_commit = ->(match) { handle_match_commit(match, type, item, line, assembla_ticket_nr, jira_ticket_key, $1, $2) }
      # IMPORTANT: @re_comment MUST precede @re_ticket
      line_after = line.
        gsub(@re_comment, &blk).
        gsub(@re_ticket, &blk).
        gsub(@re_commit, &blk_commit)
    end
    lines_after << line_after
    if line_before != line_after
      if @dry_run
        info = "#{type} assembla_ticket_nr='#{assembla_ticket_nr}' jira_ticket_key='#{jira_ticket_key}' line='#{index + 1}'"
        if type == 'comment'
          info += " assembla_comment_id='#{assembla_comment_id}' jira_comment_id='#{jira_comment_id}'"
        end
        info += " line='#{index + 1}'"
        puts "CCC: -----#{info}-----"
        puts "CCC: #{line_before}"
        puts "CCC: #{line_after}"
      end
      lines_changed = true
    end
  end
  if lines_changed
    # puts "BEFORE:\n'#{lines_before.join("\n")}'\nAFTER:\n'#{lines.join("\n")}'"
    @list_external_updated << {
      type: type,
      assembla_ticket_nr: assembla_ticket_nr,
      jira_ticket_key: jira_ticket_key,
      assembla_comment_id: assembla_comment_id,
      jira_comment_id: jira_comment_id,
      before: "#{first_line}\n#{lines_before.join("\n")}",
      after: "#{first_line}\n#{lines_after.join("\n")}"
    }
  end
end

@tickets_jira.each do |item|
  collect_list_external_all('ticket', item)
end

@comments_jira.each do |item|
  collect_list_external_all('comment', item)
end

if @missing_issue_keys.count.nonzero?
  puts "\nMissing jira issue keys: #{@missing_issue_keys.count}"
  @missing_issue_keys.each do |space, ids|
    puts "* space='#{space}'"
    ids.each do |id, count|
      puts "  id='#{id}' #{count}"
    end
  end
end

if @missing_comment_ids.count.nonzero?
  puts "\nMissing jira comment ids: #{@missing_comment_ids.count}"
  @missing_comment_ids.each do |space, ids|
    puts "* space='#{space}'"
    ids.each do |id, count|
      puts "  id='#{id}' #{count}"
    end
  end
end

if @cannot_find_commit_url.count.nonzero?
  puts "\nCannot find commit urls: #{@cannot_find_commit_url.count}"
  @cannot_find_commit_url.each do |url, count|
    puts "* url='#{url}' (#{count})"
  end
end

puts "\nTotal spaces: #{@spaces.count}"
@spaces.each do |k, v|
  puts "* #{k} (#{v}) => #{@projects.detect { |project| project[:space] == k } ? 'OK' : 'SKIP'}"
end
puts

write_csv_file("#{OUTPUT_DIR_JIRA}/jira-links-external-all.csv", @list_external_all)
write_csv_file("#{OUTPUT_DIR_JIRA}/jira-links-external-updated.csv", @list_external_updated)

@projects.each do |project|
  space = project[:space]
  rows = @list_external_all.select { |row| row[:space] == space }
  puts "\n#{space} => #{rows.count}"
  rows.each do |row|
    puts "* #{row[:type]} '#{row[:match]}' => '#{row[:replace_with]}'"
  end
end

# Go to work!

@all_external_tickets = @list_external_updated.select { |x| x[:type] == 'ticket' }
@all_external_comments = @list_external_updated.select { |x| x[:type] == 'comment' }

puts "\nTotal tickets: #{@all_external_tickets.count}"
@all_external_tickets.sort { |x, y| x[:jira_ticket_key] <=> y[:jira_ticket_key] }.each do |ticket|
  issue_key = ticket[:jira_ticket_key]
  description = ticket[:after]
  puts "jira_update_issue_description() issue_key='#{issue_key}'"
  puts '-----description (start) -----'
  puts description
  puts '-----description (finish) -----'
  # jira_update_issue_description(issue_key, description) unless @dry_run
end

puts "\nTotal comments: #{@all_external_comments.count}"
@all_external_comments.sort { |x, y| x[:jira_comment_id] <=> y[:jira_comment_id] }.each do |comment|
  issue_key = comment[:jira_ticket_key]
  comment_id = comment[:jira_comment_id]
  body = comment[:after]
  puts "jira_update_comment_body() issue_key='#{issue_key}' comment_id='#{comment_id}'"
  puts '-----body (start)-----'
  puts body
  puts '-----body (finish)-----'
  # jira_update_comment_body(issue_key, comment_id, body) unless @dry_run
end
