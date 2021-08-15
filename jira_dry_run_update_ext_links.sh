#!/bin/bash

#./jira_dry_run_update_ext_links.sh >jira_dry_run_update_ext_links.log 2>&1

COMPANY=${COMPANY:-kpmg-it}

FILES=$(ls -1 .env."$COMPANY".*)

$FILES
for FILE in $FILES; do
  echo
  echo "**** $FILE ****"
  cp "$FILE" .env
  ruby 20-jira_update_ext_links.rb dry_run=true
done
