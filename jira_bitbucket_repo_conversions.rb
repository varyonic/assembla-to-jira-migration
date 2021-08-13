# frozen_string_literal: true

load './lib/common.rb'

DELIMITER = '|||'

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

# assembla_space_ey,assembla_space_name,assembla_repo_name,bitbucket_repo_name,bitbucket_repo_url,assembla_repo_url
repos = csv_to_array(BITBUCKET_REPO_CONVERSIONS)

puts "Number of entries: #{repos.count}"
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
  puts 'Exit'
  exit
end

puts 'All required column names have been found:'
column_names.each do |column_name|
  puts "* #{column_name}"
end

conversions = {}
repos.each do |repo|
  assembla_space_key = repo['assembla_space_key']
  assembla_space_name = repo['assembla_space_name']
  assembla_repo_name = repo['assembla_repo_name']
  assembla_repo_url = repo['assembla_repo_url']
  bitbucket_repo_name = repo['bitbucket_repo_name']
  bitbucket_repo_url = repo['bitbucket_repo_url']

  conversions_key = "#{assembla_space_key}#{DELIMITER}#{assembla_space_name}"
  conversions[conversions_key] ||= []
  conversions[conversions_key] << {
    assembla_repo_name: assembla_repo_name,
    assembla_repo_url: assembla_repo_url,
    bitbucket_repo_name: bitbucket_repo_name,
    bitbucket_repo_url: bitbucket_repo_url
  }
end

conversions.each do |key, values|
  (assembla_space_key, assembla_space_name) = key.split(DELIMITER)
  puts "#{assembla_space_key} | #{assembla_space_name}"
  values.each do |value|
    assembla_repo_name = value[:assembla_repo_name]
    assembla_repo_url = value[:assembla_repo_url]
    bitbucket_repo_name = value[:bitbucket_repo_name]
    bitbucket_repo_url = value[:bitbucket_repo_url]
    puts "* assembla repo_name=#{assembla_repo_name} repo_url='#{assembla_repo_url}'"
    puts "  bitbucket repo_name='#{bitbucket_repo_name}' repo_url='#{bitbucket_repo_url}'"
  end
end
