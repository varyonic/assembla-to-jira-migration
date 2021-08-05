# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

if BITBUCKET_REPO_URL
  puts "BITBUCKET_REPO_URL = #{BITBUCKET_REPO_URL}"
else
  puts 'BITBUCKET_REPO_URL is not defined in the .env file'
  exit
end

repo_table = {}

if BITBUCKET_REPO_TABLE
  puts "BITBUCKET_REPO_TABLE = #{BITBUCKET_REPO_TABLE}"
  BITBUCKET_REPO_TABLE.split(',').each do |item|
    (from, to) = item.split('|')
    repo_table[from] = to
  end
else
  puts 'BITBUCKET_REPO_TABLE is not defined in the .env file'
  exit
end

comments_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/ticket-comments.csv"
# id,comments,user_id,created_on,updated_at,ticket_changes,user_name,user_avatar_url,ticket_id,ticket_number
@comments_assembla = csv_to_array(comments_assembla_csv)

re = /Commit: \[\[(?:.*):([0-9a-f]+)\|(.*):(?:.*)\]\]/i

@comments_assembla.each do |comment|
  comments = comment['comment']
  next unless comments&.match?(/^Commit\: /)
  m = comments&.match(re)
  next unless m && m[1] && m[2]
  match = m[0]
  commit_hash = m[1]
  from = m[2]
  to = repo_table[from]
  if to.nil?
    comments.sub!(re, match + "\nERROR: Cannot find repo entry for '#{from}'")
  else
    url = "#{BITBUCKET_REPO_URL.sub('[[REPO-NAME]]', to)}/#{commit_hash}"
    comments.sub!(re, "Assembla " + match + "\nCommit: #{url}")
  end
  puts comments
end
