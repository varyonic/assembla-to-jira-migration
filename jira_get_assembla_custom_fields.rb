# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

custom_fields_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/tickets-custom-fields.csv"
# id,comments,user_id,created_on,updated_at,ticket_changes,user_name,user_avatar_url,ticket_id,ticket_number
@custom_fields_assembla = csv_to_array(custom_fields_assembla_csv)

@custom_fields_assembla.each do |custom_field|
  type = custom_field['type']
  title = custom_field['title']
  list_options = custom_field['list_options']
  puts "#{type} | #{title}"
  next if list_options.nil?
  options = JSON.parse(list_options)
  options.each do |option|
    puts "* #{option}"
  end
end
