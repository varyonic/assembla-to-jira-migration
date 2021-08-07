# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

# Convert 'john.doe@company.com' to 'john.doe_@_company.com'
# Do not convert @example.org or admin email, e.g. leave unchanged
def mangle_email(email)
  return email if email == JIRA_API_ADMIN_EMAIL
  m = email.split('@')
  return email if m[1] == 'example.org'
  "#{m[0]}_@_#{m[1]}"
end

if MANGLE_EXTERNAL_EMAILS_NOT.count.zero?
  puts "MANGLE_EXTERNAL_EMAILS_NOT = '#{MANGLE_EXTERNAL_EMAILS_NOT}' is empty"
  exit
end

puts "MANGLE_EXTERNAL_EMAILS_NOT = '#{MANGLE_EXTERNAL_EMAILS_NOT}'"
MANGLE_EXTERNAL_EMAILS_NOT.each do |suffix|
  puts "* #{suffix}"
end

users_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/report-users.csv"
@users_assembla = csv_to_array(users_assembla_csv)
goodbye('Cannot get users!') unless @users_assembla.length.nonzero?

@users_assembla.each do |user|
  name = user['name']
  email = user['email']
  if email.nil?
    puts "name='#{name}' NO EMAIL"
  else
    suffix = '@' + email.split('@')[1]
    if MANGLE_EXTERNAL_EMAILS_NOT.include?(suffix)
      puts "name='#{name}' INTERNAL suffix='#{suffix}' email='#{email}'"
    else
      email_mangled = mangle_email(email)
      puts "name='#{name}' EXTERNAL suffix='#{suffix}' email='#{email}' => #{email_mangled}"
    end
  end
end
