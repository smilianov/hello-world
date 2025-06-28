# My Command Line CheatShit

## File Management
- `ls -la`: List all files, including hidden, in long format
- `cd ~/path`: Change to a directory (e.g., cd ~/projects)
- `rm -rf dir`: Delete directory and contents (use cautiously)

## Networking
- `ping google.com`: Test connectivity to a host
- `curl -O <url>`: Download a file from a URL

## Git
- `git status`: Check repository status
- `git commit -m "msg"`: Commit changes with a message
## My Commands
- `grep -r Уволни /home/frappe/frappe-bench`:Search in file text for word "Уволни"
## ErpNG
# clear Frappe’s caches (including translations)
- `bench --site erptest.ess.bg clear-cache`

# run any outstanding schema/patch migrations (and rebuild .po/.mo files)
- `bench --site erptest.ess.bg migrate`

# rebuild your JS/CSS so the new translations get compiled into the client
- `bench build`
