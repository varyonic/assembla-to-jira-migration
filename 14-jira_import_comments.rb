# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

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

@repo_table = {}
@missing_repos = {}

def insert_bitbucket_repo_link(body)
  re = /Commit: \[\[(?:.*):([0-9a-f]+)\|(.*):(?:.*)\]\]/i
  if body&.match?(/^Commit\: /)
    m = body&.match(re)
    if m && m[1] && m[2]
      match = m[0]
      commit_hash = m[1]
      from = m[2]
      to = @repo_table[from]
      if to.nil?
        # Keep track of missing repos and display at end.
        @missing_repos[from] = 0 if @missing_repos[from].nil?
        @missing_repos[from] += 1
        body.sub!(re, match + "\nERROR: Cannot find repo entry for '#{from}'")
      else
        url = "#{BITBUCKET_REPO_URL.sub('[[REPO-NAME]]', to)}/#{commit_hash}"
        body.sub!(re, "Assembla " + match + "\nCommit: #{url}")
      end
    end
  end
  body
end

# Jira tickets
# result,retries,message,jira_ticket_id,jira_ticket_key,project_id,summary,issue_type_id,issue_type_name,assignee_name,reporter_name,priority_name,status_name,labels,description,assembla_ticket_id,assembla_ticket_number,milestone_name,story_rank
tickets_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-tickets.csv"
@tickets_jira = csv_to_array(tickets_jira_csv).select { |ticket| ticket['result'] == 'OK' }

@is_ticket_id = {}
@tickets_jira.each do |ticket|
  @is_ticket_id[ticket['assembla_ticket_id']] = true
end

# Assembla comments
# id,comment,user_id,created_on,updated_at,ticket_changes,user_name,user_avatar_url,ticket_id,ticket_number
comments_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/ticket-comments.csv"
@comments_assembla = csv_to_array(comments_assembla_csv)

puts "Total comments: #{@comments_assembla.length}"

# TEST
@comments_assembla.select! { |c| @is_ticket_id[c['ticket_id']] }

puts "Total comments after: #{@comments_assembla.length}"

# Ignore empty comments?
if JIRA_API_SKIP_EMPTY_COMMENTS
  comments_assembla_empty = @comments_assembla.select { |comment| comment['comment'].nil? || comment['comment'].strip.empty? }
  if comments_assembla_empty && comments_assembla_empty.length.nonzero?
    @comments_assembla.reject! { |comment| comment['comment'].nil? || comment['comment'].strip.empty? }
    comments_empty_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-comments-skipped-empty.csv"
    write_csv_file(comments_empty_jira_csv, comments_assembla_empty)
    puts "Empty: #{comments_assembla_empty.length}"
    comments_assembla_empty = nil
  else
    puts "Empty: None"
  end
end

# Ignore commit comments?
if JIRA_API_SKIP_COMMIT_COMMENTS
  comments_assembla_commit = @comments_assembla.select { |comment| /Commit: \[\[r:/.match(comment['comment']) }
  if comments_assembla_commit && comments_assembla_commit.length.nonzero?
    @comments_assembla.reject! { |comment| /Commit: \[\[r:/.match(comment['comment']) }
    comments_commit_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-comments-skipped-commit.csv"
    write_csv_file(comments_commit_jira_csv, comments_assembla_commit)
    puts "Commit: #{comments_assembla_commit.length}"
    comments_assembla_commit = nil
  else
    puts 'Commit: None'
  end
else
  # Commits (comments) will be included as part of the import.
  if BITBUCKET_REPO_URL
    puts "BITBUCKET_REPO_URL = #{BITBUCKET_REPO_URL}"
    if BITBUCKET_REPO_TABLE
      puts "BITBUCKET_REPO_TABLE = #{BITBUCKET_REPO_TABLE}"
      BITBUCKET_REPO_TABLE.split(',').each do |item|
        (from, to) = item.split('|')
        @repo_table[from] = to
      end
      puts 'The following repos translations will be made:'
      @repo_table.each do |key, value|
        puts " * #{key} => #{value}"
      end
    else
      puts 'BITBUCKET_REPO_TABLE is not defined in the .env file'
    end
  else
    puts 'BITBUCKET_REPO_URL is not defined in the .env file'
  end
end

puts "Remaining: #{@comments_assembla.length}" if JIRA_API_SKIP_EMPTY_COMMENTS || JIRA_API_SKIP_COMMIT_COMMENTS

# @users_jira => assemblaId,assemblaLogin,emailAddress,accountId,accountType,emailAddress,displayName,active
users_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-users.csv"
@users_jira = csv_to_array(users_jira_csv)

@user_id_to_login = {}
@user_id_to_email = {}
@assembla_login_to_jira_id = {}
@assembla_login_to_jira_name = {}
@a_user_id_to_j_user_name = {}
@a_user_id_to_j_user_id = {}
@users_jira.each do |user|
  id = user['assemblaid']
  login = user['assemblalogin'].sub(/@.*$/, '')
  email = user['emailaddress']
  if email.nil? || email.empty?
    email = "#{login}@#{JIRA_API_DEFAULT_EMAIL}"
  end
  @user_id_to_login[id] = login
  @user_id_to_email[id] = email
  @a_user_id_to_j_user_name[id] = user['displayname']
  @a_user_id_to_j_user_id[id] = user['accountid']
  @assembla_login_to_jira_id[user['assemblalogin']] = user['accountid']
  @assembla_login_to_jira_name[user['assemblalogin']] = user['displayname']
end

# Convert assembla_ticket_id to jira_ticket_id and assembla_ticket_number to jira_ticket_key
@a_ticket_id_to_j_issue_id = {}
@a_ticket_id_to_j_issue_key = {}
@tickets_jira.each do |ticket|
  @a_ticket_id_to_j_issue_id[ticket['assembla_ticket_id']] = ticket['jira_ticket_id']
  @a_ticket_id_to_j_issue_key[ticket['assembla_ticket_id']] = ticket['jira_ticket_key']
end

# Jira attachments (images)
attachments_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-attachments-download.csv"
if File.exist?(attachments_jira_csv)
  @attachments_jira = csv_to_array(attachments_jira_csv)
else
  puts "File '#{attachments_jira_csv}' is missing, no attachments detected."
  @attachments_jira = []
end

@list_of_images = {}
@attachments_jira.each do |attachment|
  @list_of_images[attachment['assembla_attachment_id']] = attachment['filename']
end

puts "Attachments: #{@attachments_jira.length}"
puts

# --- Filter by date if TICKET_CREATED_ON is defined --- #
tickets_created_on = get_tickets_created_on

if tickets_created_on
  puts "Filter newer than: #{tickets_created_on}"
  comments_initial = @comments_assembla.length
  # Only want comments which belong to remaining tickets
  @comments_assembla.select! { |item| @a_ticket_id_to_j_issue_id[item['ticket_id']] }
  puts "Comments: #{comments_initial} => #{@comments_assembla.length} ∆#{comments_initial - @comments_assembla.length}"
end
puts "Tickets: #{@tickets_jira.length}"

@comments_total = @comments_assembla.length

def headers_user_login_comment(user_login, user_email)
  # Note: Jira cloud doesn't allow the user to create own comments, a user belonging to the jira-administrators
  # group must do that.
  headers_user_login(user_login, user_email)
  # {'Authorization': "Basic #{Base64.strict_encode64(user_login + ':' + user_login)}", 'Content-Type': 'application/json; charset=utf-8'}
end

@comments_diffs_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-comments-diffs.csv"
@total_comments_diffs = 0

# POST /rest/api/2/issue/{issueIdOrKey}/comment
def jira_create_comment(issue_id, user_id, comment, counter)
  result = nil
  url = "#{URL_JIRA_ISSUES}/#{issue_id}/comment"
  user_login = @a_user_id_to_j_user_name[user_id]
  user_id = @a_user_id_to_j_user_id[user_id]
  if user_login
    user_email = @user_id_to_email[user_id]
  else
    user_login = JIRA_API_UNKNOWN_USER
    user_email = user_login + '@' + JIRA_API_DEFAULT_EMAIL
  end
  # headers = headers_user_login_comment(user_login, user_email)
  headers = JIRA_HEADERS_ADMIN
  comment_comment = if comment['comment'].nil? || comment['comment'].strip.empty?
                      comment['ticket_changes']
                    else
                      comment['comment']
                    end
  comment_comment = insert_bitbucket_repo_link(comment_comment) unless @repo_table.empty?
  reformatted_body = reformat_markdown(comment_comment, user_ids: @assembla_login_to_jira_id,
                                       images: @list_of_images, content_type: 'comments', strikethru: true)
  body = "Created on #{date_time(comment['created_on'])}\n\n#{reformatted_body}"
  if JIRA_SERVER_TYPE == 'cloud'
    author_link = user_id ? "[~accountid:#{user_id}]" : "unknown (#{user_id})"
    body = "Author #{author_link} | #{body}"
  end
  body = "Assembla | #{body}"
  # Ensure that the body is not too long.
  if body.length > 32767
    body = body[0..32760] + '...'
    warning('Comment body length is greater than 32767 => truncate')
  end
  payload = {
    body: body
  }.to_json
  percentage = ((counter * 100) / @comments_total).round.to_s.rjust(3)
  if @dry_run
    puts "----- jira_create_comment() issue_id='#{issue_id}' user_login='#{user_login}' comment_id='#{comment['id']}', counter='#{counter}' -----" if @dry_run
    puts body
    puts '----- end -----'
    return
  end
  begin
    response = RestClient::Request.execute(method: :post, url: url, payload: payload, headers: headers)
    result = JSON.parse(response.body)
    # Dry run: uncomment the following two lines and comment out the previous two lines.
    # result = {}
    # result['id'] = counter
    puts "#{percentage}% [#{counter}|#{@comments_total}] POST #{url} => OK"
  rescue RestClient::ExceptionWithResponse => e
    # TODO: use following helper method for all RestClient calls in other files.
    rest_client_exception(e, 'POST', url)
  rescue => e
    puts "#{percentage}% [#{counter}|#{@comments_total}] POST #{url} => NOK (#{e.message})"
  end
  if result && comment_comment != reformatted_body
    id = comment['id']
    ticket_id = comment['ticket_id']
    issue_id = @a_ticket_id_to_j_issue_id[ticket_id]
    issue_key = @a_ticket_id_to_j_issue_key[ticket_id]
    comment_id = result['id']
    comments_diff = {
      jira_comment_id: comment_id,
      jira_ticket_id: issue_id,
      jira_ticket_key: issue_key,
      assembla_comment_id: id,
      assembla_ticket_id: ticket_id,
      before: comment_comment,
      after: reformatted_body
    }
    write_csv_file_append(@comments_diffs_jira_csv, [comments_diff], @total_comments_diffs.zero?)
    @total_comments_diffs += 1
  end
  result
end

# IMPORTANT: Make sure that the comments are ordered chronologically from first (oldest) to last (newest)
@comments_assembla.sort! { |x, y| x['created_on'] <=> y['created_on'] }

@total_imported = 0
@total_imported_nok = 0
@comments_jira_csv = "#{OUTPUT_DIR_JIRA}/jira-comments.csv"
@comments_jira_nok_csv = "#{OUTPUT_DIR_JIRA}/jira-comments-nok.csv"

@comments_assembla.each_with_index do |comment, index|
  result = nil
  id = comment['id']
  counter = index + 1
  ticket_id = comment['ticket_id']
  user_id = comment['user_id']
  issue_id = @a_ticket_id_to_j_issue_id[ticket_id]
  issue_key = @a_ticket_id_to_j_issue_key[ticket_id]
  user_login = @user_id_to_login[user_id]
  body = comment['comment']
  if issue_id.nil? || issue_id.length.zero?
    warning("Cannot find jira_issue_id for assembla_ticket_id='#{ticket_id}'")
  else
    result = jira_create_comment(issue_id, user_id, comment, counter)
  end

  next if @dry_run

  if result
    comment_id = result['id']
    comment = {
      jira_comment_id: comment_id,
      jira_ticket_id: issue_id,
      jira_ticket_key: issue_key,
      assembla_comment_id: id,
      assembla_ticket_id: ticket_id,
      user_login: user_login,
      body: body
    }
    write_csv_file_append(@comments_jira_csv, [comment], @total_imported.zero?)
    @total_imported += 1
  else
    comment_nok = {
      error: issue_id.nil? ? 'invalid ticket_id' : 'create failed',
      assembla_ticket_id: ticket_id,
      assembla_comment_id: id,
      user_login: user_login,
      body: body
    }
    write_csv_file_append(@comments_jira_nok_csv, [comment_nok], @total_imported_nok.zero?)
    @total_imported_nok += 1
  end
end

unless @missing_repos.count.zero?
  puts "\nWARNING: The following repos were detected but NOT found in BITBUCKET_REPO_TABLE"
  @missing_repos.each do |repo, count|
    puts "* #{repo} (#{count})"
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
  puts "Total imported: #{@total_imported}"
  puts @comments_jira_csv

  puts "Total diffs: #{@total_comments_diffs}"
  puts @comments_diffs_jira_csv

  puts "Total NOK: #{@total_imported_nok}"
  puts @comments_jira_nok_csv
end

