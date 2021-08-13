# frozen_string_literal: true

load './lib/common.rb'

puts
unless File.exist?(BITBUCKET_REPO_CONVERSIONS)
  puts "File BITBUCKET_REPO_CONVERSION='#{BITBUCKET_REPO_CONVERSIONS}' doesn't exist"
  exit
end

puts "Found file '#{BITBUCKET_REPO_CONVERSIONS}'"

column_names = %w{
  assembla_space_key
  assembla_space_name
  assembla_repo_name
  bitbucket_repo_name
  bitbucket_repo_url
  assembla_repo_url
}

# Assembla Space Key,Assembla Space Name,Assembla Repo Name,BitBucket Repo Name,Bitbucket Repo URL,Assembla Repo URL
repos = csv_to_array(BITBUCKET_REPO_CONVERSIONS)

puts "Number of entries: #{repos.count}"
if repos.count.zero?
  puts 'There are no entries found => Exit'
  exit
end

# Make sure that all of the columns are present.
repo = repos.first
missing_column_names = []
column_names.each do |column_name|
  missing_column_names << column_name if repo[column_name].nil?
end

unless missing_column_names.count.zero?
  puts 'The following columns are missing:'
  missing_column_names.each do |missing_column_name|
    puts "* #{missing_column_name}"
  end
  puts 'Exit'
  exit
end

puts 'All required column names have been found:'
column_names.each do |column_name|
  puts "* #{column_name}"
end
