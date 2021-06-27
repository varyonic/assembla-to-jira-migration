# frozen_string_literal: true

load './lib/common.rb'

load './lib/users-jira.rb'

@names = []

# name,key,accountId,emailAddress,displayName,active
jira_get_all_groups.each_with_index do |group, index|
  @names << group['name']
end

@names.each_with_index do |name, index|
  puts "#{index + 1}. #{name}"
end

puts
puts @names.join(',')
