# frozen_string_literal: true

load './lib/common.rb'

FILE_TOOL_ID = 18

spaces_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/spaces.csv"

puts
unless File.exist?(spaces_assembla_csv)
  puts "File '#{spaces_assembla_csv}' does not exists"
  exit
end

@spaces_assembla = csv_to_array(spaces_assembla_csv)

assembla_space = @spaces_assembla.detect {|space| space['name'] == ASSEMBLA_SPACE}

if assembla_space.nil?
  puts "Space '#{ASSEMBLA_SPACE}' does not exist"
  exit
end

space_id = assembla_space['id']
puts "Found space '#{ASSEMBLA_SPACE}' space_id='#{space_id}'"
url = "#{ASSEMBLA_API_HOST}/spaces/#{space_id}/space_tools/#{FILE_TOOL_ID}/add"
begin
  response = RestClient::Request.execute(method: :post, url: url, headers: ASSEMBLA_HEADERS)
  puts "POST #{url} => OK"
  result = JSON.parse(response.body)
  puts result.inspect unless result.nil?
rescue => e
  puts "POST #{url} => NOK (#{e.message})"
end
