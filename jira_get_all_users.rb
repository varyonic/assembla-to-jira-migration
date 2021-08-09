# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

@all_users = []

@display_names = {}

# accountId,displayName,active,accountType
@users = jira_get_all_users
puts "\nTotal users: #{@users.count}"
@users.each do |user|
  id = user['accountId']
  display_name = user['displayName']
  user = jira_get_user(id, true)
  groups = user['groups']
  groups['items'].each do |item|
    user['group:' + item['name']] = true
  end
  @all_users << user
  if @display_names[display_name]
    @display_names[display_name] << id
  else
    @display_names[display_name] = [id]
  end
end

puts
# Check for possible duplicate display names
@display_names.each do |key, value|
  next if value.count == 1
  puts "There are multiple users with display name '#{key}':"
  value.each do |id|
    puts "* #{id}"
  end
end

puts
filename = 'jira_get_all_users.csv'
write_csv_file(filename, @all_users)
