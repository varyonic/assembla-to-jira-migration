bitbucket_repo_url = 'https://bitbucket.org/kpmg-it-lh/asf.p.nop-plugin-widget-productdocumentupload/commits'

s = 'Commit: [[r:18:544669746ec15b32ca1c0f87cad99faadb189c81|ania.nop_plugin_productDocUpload:544669746e]]'
re = /Commit: \[\[(?:.*):([0-9a-f]+)\|(?:.*):(?:.*)\]\]/i

(_, commit_hash) = s.match(re)

url = "#{bitbucket_repo_url}/#{commit_hash}"

puts url
