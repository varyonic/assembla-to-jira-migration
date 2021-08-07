# frozen_string_literal: true

load './lib/common.rb'
load './lib/users-jira.rb'

# Convert 'john.doe@company.com' to 'john.doe_@_company.com'
# Do not convert @example.org or admin email, e.g. leave unchanged
def mangle_email(email)
  return email if email.downcase == JIRA_API_ADMIN_EMAIL || MANGLE_EXTERNAL_EMAILS_NOT_IGNORE.include?(email.downcase)
  m = email.split('@')
  return email if m[1] == 'example.org'
  "#{m[0]}z@z#{m[1]}"
end

puts
if MANGLE_EXTERNAL_EMAILS_NOT.count.zero?
  puts "MANGLE_EXTERNAL_EMAILS_NOT = '#{MANGLE_EXTERNAL_EMAILS_NOT}' is empty"
  exit
end

puts "MANGLE_EXTERNAL_EMAILS_NOT = '#{MANGLE_EXTERNAL_EMAILS_NOT}'"
MANGLE_EXTERNAL_EMAILS_NOT.each do |suffix|
  puts "* #{suffix}"
end

puts
if MANGLE_EXTERNAL_EMAILS_NOT_IGNORE.count.zero?
  puts "MANGLE_EXTERNAL_EMAILS_NOT_IGNORE = '#{MANGLE_EXTERNAL_EMAILS_NOT_IGNORE}' is empty (no emails will be ignored)"
else
  puts "MANGLE_EXTERNAL_EMAILS_NOT_IGNORE = '#{MANGLE_EXTERNAL_EMAILS_NOT_IGNORE}'"
  MANGLE_EXTERNAL_EMAILS_NOT_IGNORE.each do |email|
    puts "* #{email}"
  end
end

users_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/report-users.csv"
@users_assembla = csv_to_array(users_assembla_csv)
goodbye('Cannot get users!') unless @users_assembla.length.nonzero?

@mangled = []
@not_mangled = []

@users_assembla.each do |user|
  name = user['name']
  email = user['email']
  if email.nil?
    puts "name='#{name}' NO EMAIL"
  else
    suffix_with_at = '@' + email.split('@')[1]
    if MANGLE_EXTERNAL_EMAILS_NOT.include?(suffix_with_at.downcase)
      @not_mangled << "name='#{name}' INTERNAL suffix='#{suffix_with_at}' email='#{email}'"
    else
      email_mangled = mangle_email(email)
      if email_mangled == email
        @not_mangled << "name='#{name}' EXTERNAL IGNORE suffix='#{suffix_with_at}' email='#{email}'"
      else
        @mangled << "name='#{name}' EXTERNAL MANGLE suffix='#{suffix_with_at}' email='#{email}' => #{email_mangled}"
      end
    end
  end
end

puts "\nThe following emails WILL NOT be mangled:"
@not_mangled.each { |text| puts " * #{text}" }

puts "\nThe following emails WILL be mangled:"
@mangled.each { |text| puts " * #{text}" }
