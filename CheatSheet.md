# My Command Line CheatShit

## File Management
- `ls -lash`: List all files, including hidden, in long format
- `cd ~/path`: Change to a directory (e.g., cd ~/projects)
- `rm -rf dir`: Delete directory and contents (use cautiously)
- `sudo chmod -R u+rwx /srv/dev-disk-by-uuid-08a6cb6b-5e4b-473c-9c86-ae436ea37039/work/Gun/Temp`: Change ownership of Directory

## Networking
- `ping google.com`: Test connectivity to a host
- `curl -O <url>`: Download a file from a URL

## Git
- `git status`: Check repository status
- `git commit -m "msg"`: Commit changes with a message
## My Commands
- `grep -r Уволни /home/frappe/frappe-bench`:Search in file text for word "Уволни"


# ErpNG
## /home/frappe/frappe-bench/apps/erpnext/erpnext/crm/workspace/crm/crm.json

## Edit translation
- `nano /home/frappe/frappe-bench/apps/frappe/frappe/translations/bg.csv`
## clear Frappe’s caches (including translations)
- `bench --site erptest.ess.bg clear-cache`

## run any outstanding schema/patch migrations (and rebuild .po/.mo files)
- `bench --site erptest.ess.bg migrate`

## rebuild your JS/CSS so the new translations get compiled into the client
- `bench build`
