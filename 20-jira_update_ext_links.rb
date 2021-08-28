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
      goodbye("SANITY CHECK: Cannot find correct bitbucket_repo_url='#{bitbucket_repo_url}' for assembla_space_key='#{assembla_space_key}' assembla_repo_url='#{assembla_repo_url}'")
    end
  end

  puts "All sanity checks pass"
else
  puts "File BITBUCKET_REPO_CONVERSION='#{BITBUCKET_REPO_CONVERSIONS}' doesn't exist"
end

@assembla_spaces = csv_to_array("#{OUTPUT_DIR_ASSEMBLA}/spaces.csv")
@a_space_id_to_wiki_name = {}
@a_wiki_name_to_space_name = {}
puts "\nTotal assembla spaces: #{@assembla_spaces.count}"
@assembla_spaces.each do |space|
  id = space['id']
  name = space['name']
  wiki_name = space['wiki_name']
  @a_space_id_to_wiki_name[id] = wiki_name
  @a_wiki_name_to_space_name[wiki_name] = name
  puts "* id='#{id}' name='#{name}' wiki_name='#{wiki_name}'"
end
puts

@all_projects = jira_get_projects
@all_a_id_to_j_id = {}

@projects = []

puts "\nJIRA_API_SPACE_TO_PROJECT='#{JIRA_API_SPACE_TO_PROJECT}'"
JIRA_API_SPACE_TO_PROJECT.split(',').each do |item|

  @cannot_find_comments = ''
  space, key = item.split(':')

  goodbye("Missing space, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless space
  goodbye("Missing key, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless key

  project = @all_projects.detect { |p| p['key'] == key }
  goodbye("Cannot find project with key=#{key}, item=#{item}, JIRA_API_SPACE_TO_PROJECT=#{JIRA_API_SPACE_TO_PROJECT}") unless project
  project_name = project['name']

  output_dir = output_dir_jira(space)

  csv_tickets = "#{output_dir}/jira-tickets.csv"
  goodbye("Cannot find file '#{csv_tickets}' for space='#{space}' key='#{key}'") unless File.exist?(csv_tickets)
  tickets = csv_to_array(csv_tickets).select { |ticket| ticket['result'] == 'OK' }

  csv_comments = "#{output_dir}/jira-comments.csv"
  if File.exist?(csv_comments)
    comments = csv_to_array(csv_comments)
  else
    comments = []
    @cannot_find_comments = " (cannot find file '#{csv_comments}', will continue anyway)"
  end

  ticket_a_nr_to_j_key = {}
  tickets.each do |ticket|
    assembla_ticket_id = ticket['assembla_ticket_id']
    jira_ticket_id = ticket['jira_ticket_id']
    ticket_a_nr_to_j_key[ticket['assembla_ticket_number']] = ticket['jira_ticket_key']
    @all_a_id_to_j_id[assembla_ticket_id] = jira_ticket_id
  end

  comment_a_id_to_j_id = {}
  comments.each do |comment|
    comment_a_id_to_j_id[comment['assembla_comment_id']] = comment['jira_comment_id']
  end

  puts "* space='#{space}' key='#{key}' project_name='#{project_name}' | tickets: #{tickets.count} | comments: #{comments.count}#{@cannot_find_comments}"

  @projects << {
    space: space,
    key: key,
    name: project_name,
    output_dir: output_dir,
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

@missing_issue_ids = {}

# Convert the Assembla ticket id to the associated Jira issue id
def link_ticket_a_id_to_j_id(assembla_ticket_id)
  jira_issue_id = nil
  @projects.each do |project|
    next unless jira_issue_id.nil?
    jira_issue_id = project[:ticket_a_id_to_j_id][assembla_ticket_id]
  end
  unless jira_issue_id
    @missing_issue_ids[assembla_ticket_id] = 0 unless @missing_issue_ids[assembla_ticket_id]
    @missing_issue_ids[assembla_ticket_id] += 1
  end
  jira_issue_id
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
@missing_projects = {}

def get_project_by_space(space)
  project = @project_by_space[space]
  if project.nil?
    # It's possible that in the link rather than using the 'space name', it uses the 'space id' instead, adapt to this
    # situation also.
    converted_space = @converted_spaces[space]
    if converted_space
      project = @project_by_space[converted_space]
    else
      # Assembla BUG: Could 'space' actually be the wiki_name?
      space_name = @a_wiki_name_to_space_name[space]
      if space_name
        @converted_spaces[space] = space_name
        puts "get_project_by_space() space='#{space}' converted to space_name='#{space_name}'"
        project = @project_by_space[space_name]
        if project.nil?
          # This should logically be impossible, but you never know for sure.
          unless @missing_projects[space]
            puts "Cannot find project for space='#{space}' => SKIP"
            @missing_projects[space] = true
          end
        end
      else
        unless @missing_projects[space]
          puts "Cannot find project for space='#{space}' => SKIP"
          @missing_projects[space] = true
        end
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

# https?://.*?\.assembla\.com/spaces/(.*?)/git/commits/[:hash]
@re_commit = %r{https?://.*?\.assembla\.com/spaces/(.*?)/git/commits/([a-z0-9]+)}

# => https://bitbucket.org/[:company-name]/[[REPO-NAME]]/commits/[:commit_hash]'

@list_external_all = []
@list_external_updated = []
@spaces = {}

@cannot_find_commit_url = {}
@matched_commit_urls = []

def handle_match_commit(match, type, item, line, assembla_ticket_nr, jira_ticket_key, assembla_repo_url, hash)
  # puts "handle_match_commit() match='#{match}' type='#{type}' line='#{line}' assembla_ticket_nr='#{assembla_ticket_nr}' jira_ticket_key='#{jira_ticket_key}' assembla_repo_url='#{assembla_repo_url}' hash='#{hash}'"
  replace_with = match
  if BITBUCKET_REPO_URL
    to = @bitbucket_from_to_url[assembla_repo_url]
    if to
      replace_with = "#{BITBUCKET_REPO_URL.sub('[[REPO-NAME]]', to)}/#{hash}"
      @matched_commit_urls << {
        assembla_repo_url: assembla_repo_url,
        replace_with: replace_with
      }
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
        puts "-----#{info}-----"
        puts "#{line_before}"
        puts "#{line_after}"
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

if @matched_commit_urls.count.nonzero?
  puts "\nMatched commit urls: #{@matched_commit_urls.count}"
  @matched_commit_urls.each do |item|
    from = item[:assembla_repo_url]
    to = item[:replace_with]
    puts "* '#{from}' => '#{to}'"
  end
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

if @missing_issue_ids.count.nonzero?
  puts "\nMissing jira issue ids: #{@missing_issue_ids.count}"
  @missing_issue_ids.each do |id, count|
    puts "* id='#{id}' (#{count})"
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

if @missing_projects.count.nonzero?
  puts "\nCannot find jira projects: #{@missing_projects.count}"
  @missing_projects.each do |project, _|
    puts "* name='#{project}'"
  end
end

puts "\nTotal assembla spaces: #{@spaces.count}"
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

puts "\nTotal external tickets: #{@all_external_tickets.count}"
@all_external_tickets.sort { |x, y| x[:jira_ticket_key] <=> y[:jira_ticket_key] }.each do |ticket|
  issue_key = ticket[:jira_ticket_key]
  description = ticket[:after]
  puts "jira_update_issue_description() issue_key='#{issue_key}'"
  puts '-----description (start) -----'
  puts description
  puts '-----description (finish) -----'
  jira_update_issue_description(issue_key, description) unless @dry_run
end

puts "\nTotal external comments: #{@all_external_comments.count}"
@all_external_comments.sort { |x, y| x[:jira_comment_id] <=> y[:jira_comment_id] }.each do |comment|
  issue_key = comment[:jira_ticket_key]
  comment_id = comment[:jira_comment_id]
  body = comment[:after]
  puts "jira_update_comment_body() issue_key='#{issue_key}' comment_id='#{comment_id}'"
  puts '-----body (start)-----'
  puts body
  puts '-----body (finish)-----'
  jira_update_comment_body(issue_key, comment_id, body) unless @dry_run
end

### --- LINK ISSUES --- #

# TODO: Copied from 18-jira_update_associations.rb, need to refactor

# Jira issue link types and tickets
issuelink_types_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-issuelink-types.csv"
@issuelink_types_jira = csv_to_array(issuelink_types_jira_csv)

# Filter for ok tickets only
@is_ticket_id = {}
@tickets_jira.each do |ticket|
  @is_ticket_id[ticket['assembla_ticket_id']] = true
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

# Assembla tickets
# id,ticket1_id,ticket2_id,relationship,created_at,ticket_id,ticket_number,relationship_name
associations_csv = "#{OUTPUT_DIR_ASSEMBLA}/ticket-associations.csv"
@associations_assembla = csv_to_array(associations_csv)

# --- Filter by date if TICKET_CREATED_ON is defined --- #
tickets_created_on = get_tickets_created_on

if tickets_created_on
  puts "Filter newer than: #{tickets_created_on}"
  @associations_assembla.select! { |association| @assembla_id_to_jira[association['ticket1_id']] && @assembla_id_to_jira[association['ticket2_id']] }
end

@total_assembla_associations = @associations_assembla.length
puts "\nTotal assembla associations: #{@total_assembla_associations}"

# Filter for ok tickets only
@associations_assembla.select! { |c| @is_ticket_id[c['ticket_id']] }

@total_assembla_associations = @associations_assembla.length
puts "Total assembla associations after: #{@total_assembla_associations}"

# Collect ticket statuses
@relationship_names = {}
@relationship_tickets = {}
@associations_assembla.each do |association|
  ticket_id = association['ticket_id'].to_i
  ticket1_id = association['ticket1_id'].to_i
  ticket2_id = association['ticket2_id'].to_i
  if ticket1_id != ticket_id && ticket2_id != ticket_id
    goodbye("ticket1_id (#{ticket1_id}) != ticket_id (#{ticket_id}) && ticket2_id (#{ticket2_id}) != ticket_id (#{ticket_id})")
  end
  name = association['relationship_name']
  if @relationship_names[name].nil?
    @relationship_names[name] = 0
  else
    @relationship_names[name] += 1
  end
  @relationship_tickets[ticket_id] = { associations: {} } if @relationship_tickets[ticket_id].nil?
  @relationship_tickets[ticket_id][:associations][name] = [] if @relationship_tickets[ticket_id][:associations][name].nil?
  @relationship_tickets[ticket_id][:associations][name] << {
    ticket: ticket1_id == ticket_id ? 2 : 1,
    ticket_id: ticket1_id == ticket_id ? ticket2_id : ticket1_id
  }
end

puts "\nTotal jira issue link types: #{@issuelink_types_jira.length}"
@issuelink_types_jira.each do |issuelink_type|
  puts "* #{issuelink_type['name']}"
end

puts "\nTotal assembla relationship names: #{@relationship_names.keys.length}"
@relationship_names.each do |item|
  puts "* #{item[0]}: #{item[1]}"
end

puts "\nTotal relationship tickets: #{@relationship_tickets.keys.length}"

# POST /rest/api/2/issueLink
def jira_update_association(name, ticket1_id, ticket2_id, counter)
  result = nil
  # user_login = @jira_id_to_login[ticket_id]
  # user_login.sub!(/@.*$/, '')
  # headers = headers_user_login(user_login, user_email)
  headers = JIRA_HEADERS_ADMIN
  name.capitalize!
  name = 'Relates' if name == 'Related'
  name = 'Blocks' if name == 'Block'
  url = URL_JIRA_ISSUELINKS
  payload = {
    type: {
      name: name
    },
    inwardIssue: {
      id: "#{ticket1_id}"
    },
    outwardIssue: {
      id: "#{ticket2_id}"
    }
  }.to_json
  percentage = ((counter * 100) / @total_assembla_associations).round.to_s.rjust(3)
  begin
    RestClient::Request.execute(method: :post, url: url, payload: payload, headers: headers)
    puts "#{percentage}% [#{counter}|#{@total_assembla_associations}] PUT #{url} '#{name}' => OK"
    result = true
  rescue RestClient::ExceptionWithResponse => e
    rest_client_exception(e, 'PUT', url, payload)
  rescue => e
    puts "#{percentage}% [#{counter}|#{@total_assembla_associations}] PUT #{url} #{payload.inspect} => NOK (#{e.message})"
  end
  result
end

@total_updates = 0
@ext_associations_tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets-associations-ext-links.csv"

# Here we only want to handle the external issue associations since the known issues have already
# been handled in the previous '18-jira_update_associations.rb' script call.
@ext_associations_assembla = @associations_assembla.select do |association, index|
  is_external = false
  name = association['relationship_name']
  unless ASSEMBLA_SKIP_ASSOCIATIONS.include?(name.split.first)
    assembla_ticket1_id = association['ticket1_id']
    assembla_ticket2_id = association['ticket2_id']
    jira_ticket1_id = @assembla_id_to_jira[assembla_ticket1_id]
    jira_ticket2_id = @assembla_id_to_jira[assembla_ticket2_id]
    if jira_ticket1_id.to_i.zero?
      jira_ticket1_id = @all_a_id_to_j_id[assembla_ticket1_id]
      is_external = true
      if jira_ticket1_id.nil?
        puts "Cannot find jira_ticket1_id for association_name='#{name}' assembla_ticket1_id='#{assembla_ticket1_id}' => SKIP"
      else
        is_external = true
      end
    end
    if jira_ticket2_id.to_i.zero?
      jira_ticket2_id = @all_a_id_to_j_id[assembla_ticket2_id]
      if jira_ticket2_id.nil?
        puts "Cannot find jira_ticket2_id for association_name='#{name}' assembla_ticket2_id='#{assembla_ticket2_id}' => SKIP"
      else
        is_external = true
      end
    end
  end
  is_external
end

@total_assembla_associations = @ext_associations_assembla.length
puts "Total external assembla associations: #{@total_assembla_associations}"

@first_time = true
@ext_associations_assembla.each_with_index do |association, index|
  counter = index + 1
  name = association['relationship_name']
  assembla_ticket1_id = association['ticket1_id']
  assembla_ticket2_id = association['ticket2_id']
  assembla_ticket_id = association['ticket_id']
  jira_ticket1_id = @all_a_id_to_j_id[assembla_ticket1_id]
  jira_ticket2_id = @all_a_id_to_j_id[assembla_ticket2_id]
  if @dry_run
    percentage = ((counter * 100) / @total_assembla_associations).round.to_s.rjust(3)
    puts "#{percentage}% [#{counter}|#{@total_assembla_associations}] jira_update_association() name='#{name}' jira_ticket1_id='#{jira_ticket1_id}' jira_ticket2_id='#{jira_ticket2_id}'"
  else
    results = jira_update_association(name, jira_ticket1_id, jira_ticket2_id, counter)
    @total_updates += 1 if results
    associations_ticket = {
      result: results ? 'OK' : 'NOK',
      assembla_ticket1_id: assembla_ticket1_id,
      jira_ticket1_id: jira_ticket1_id,
      assembla_ticket2_id: assembla_ticket2_id,
      jira_ticket2_id: jira_ticket2_id,
      relationship_name: name.capitalize
    }
    write_csv_file_append(@ext_associations_tickets_jira_csv, [associations_ticket], @first_time)
    @first_time = false
  end
end

if @dry_run
  puts
  puts 'IMPORTANT!'
  puts 'Please note that DRY RUN has been enabled'
  puts "For the real McCoy, call this script with 'dry_run=false'"
  puts 'But make sure you are sure!'
  puts
else
  puts "\nTotal updates: #{@total_updates}"
  puts @ext_associations_tickets_jira_csv
end
