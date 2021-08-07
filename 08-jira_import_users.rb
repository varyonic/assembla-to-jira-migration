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
else
  puts "MANGLE_EXTERNAL_EMAILS_NOT = '#{MANGLE_EXTERNAL_EMAILS_NOT}'"
  MANGLE_EXTERNAL_EMAILS_NOT.each do |suffix|
    puts "* #{suffix}"
  end
end

# IMPORTANT: Make sure that the `JIRA_API_ADMIN_USER` exists, is activated and belongs to both
# the `site-admins` and the `jira-administrators` groups.
#
# accountId,displayName,active,accountType
@jira_administrators = jira_get_group('jira-administrators')
admin_administrator = @jira_administrators.detect { |user| user['accountId'] == JIRA_API_ADMIN_ACCOUNT_ID }

@jira_site_admins = jira_get_group('site-admins')
admin_site_admin = @jira_site_admins.detect { |user| user['accountId'] == JIRA_API_ADMIN_ACCOUNT_ID }

# You may have to uncomment out the following line to get things working
goodbye("Admin user with JIRA_API_ADMIN_ACCOUNT_ID='#{JIRA_API_ADMIN_ACCOUNT_ID}' does NOT exist or does NOT belong to both the 'jira-administrators' and the 'site-admins' groups.") unless admin_site_admin && admin_administrator

# You may have to uncomment out the following line to get things working
goodbye("Admin user with JIRA_API_ADMIN_ACCOUNT_ID='#{JIRA_API_ADMIN_ACCOUNT_ID}' is NOT active, please activate user.") unless admin_site_admin['active'] && admin_administrator['active']

# @user_assembla => count,id,login,name,picture,email,organization,phone,...
users_assembla_csv = "#{OUTPUT_DIR_ASSEMBLA}/report-users.csv"
@users_assembla = csv_to_array(users_assembla_csv)
goodbye('Cannot get users!') unless @users_assembla.length.nonzero?

# name,key,accountId,emailAddress,displayName,active
# @existing_users_jira = jira_get_users

# accountId,displayName,active,accountType
@existing_users_jira = jira_get_all_users

puts "Existings users: #{@existing_users_jira.length}"
@existing_users_jira.each do |u|
  puts "accountId='#{u['accountId']}' displayName='#{u['displayName']}' active='#{u['active']}' accountType='#{u['accountType']}'"
end

@users_jira = []
# assembla => jira
# --------    ----
# id       => assemblaId
# login    => name (optional trailing '@.*$' removed)
# email    => emailAddress
# name     => displayName

@users_assembla.each do |user|
  if user['count'].to_i.zero?
    puts "username='#{username}' zero count => SKIP"
    next
  end
  username = user['login'].sub(/@.*$/, '')
  email = user['email']
  if email.nil? || email.length.zero?
    email = "#{JIRA_API_UNKNOWN_USER}#{JIRA_API_DEFAULT_EMAIL}"
    puts "username='#{username}' does NOT have a valid email, changed to '#{email}'"
  end
  u1 = jira_get_user_by_username(@existing_users_jira, username)
  # u1 = jira_get_user_by_email(@existing_users_jira, email)
  if u1
    # User exists so add to list
    puts "username='#{username}', email='#{email}' already exists => SKIP"
    @users_jira << { 'assemblaId': user['id'], 'assemblaLogin': user['login'], 'emailAddress': user['email'] }.merge(u1)
  else
    # User does not exist so create if possible and add to list
    puts "username='#{username}', email='#{email}' not found => CREATE"
    # If enabled, we need to mangle the emails of any external users so that they
    # will not be notified during creation (because the email is invalid)
    # Important: this needs to be restored after the migration so that the user
    # can access the project as usual.
    user['email'] = mangle_email(user['email'])
    u2 = jira_create_user(user)
    if u2
      @users_jira << { 'assemblaId': user['id'], 'assemblaLogin': user['login'], 'emailAddress': user['email'] }.merge(u2)
    end
  end
end

# jira-users.csv => assemblaid,assemblalogin,emailAddress,accountid,name,displayname,active
jira_users_csv = "#{OUTPUT_DIR_JIRA}/jira-users.csv"
write_csv_file(jira_users_csv, @users_jira)

# Notify inactive users.
inactive_users = @users_jira.reject { |user| user['active'] }

unless inactive_users.length.zero?
  puts "\nIMPORTANT: The following users MUST to be activated before you continue: #{inactive_users.map { |user| user['name'] }.join(', ')}"
end
