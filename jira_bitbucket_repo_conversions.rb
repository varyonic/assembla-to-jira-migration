# frozen_string_literal: true

load './lib/common.rb'

DELIMITER = '|||'

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

@bitbucket_conversions = {}
@bitbucket_from_to_name = {}
@bitbucket_from_to_url = {}

puts
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

  puts "\nTotal assembla space keys: #{@assembla_space_keys.count}"
  @assembla_space_keys.each { |name| puts "* #{name}" }

  puts "\nTotal assembla space names: #{@assembla_space_names.count}"
  @assembla_space_names.each { |name| puts "* #{name}" }

  puts "\nTotal assembla repo names: #{@assembla_repo_names.count}"
  @assembla_repo_names.each { |name| puts "* #{name}" }

  puts "\nTotal assembla repo urls: #{@assembla_repo_urls.count}"
  @assembla_repo_urls.each { |name| puts "* #{name}" }

  puts "\nTotal bitbucket repo names: #{@bitbucket_repo_names.count}"
  @bitbucket_repo_names.each { |name| puts "* #{name}" }

  puts "\nTotal bitbucket repo_urls: #{@bitbucket_repo_urls.count}"
  @bitbucket_repo_urls.each { |name| puts "* #{name}" }

  @bitbucket_conversions.each do |key, values|
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

  # Sanity checks.
  repos.each do |repo|
    assembla_space_key = repo['assembla_space_key']
    assembla_repo_url = repo['assembla_repo_url']
    bitbucket_repo_url = repo['bitbucket_repo_url']
    unless bitbucket_repo_url == assembla_to_bitbucket_repo_url(assembla_repo_url, assembla_space_key)
      puts "Cannot find correct bitbucket_repo_url='#{bitbucket_repo_url}' for assembla_space_key='#{assembla_space_key}' assembla_repo_url='#{assembla_repo_url}'"
      exit
    end
  end

  puts "\nAll sanity checks pass"
else
  puts "File BITBUCKET_REPO_CONVERSION='#{BITBUCKET_REPO_CONVERSIONS}' doesn't exist"
end
