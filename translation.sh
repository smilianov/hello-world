#!/bin/bash
# Script by GuN®
# Edit/Add translations
# nano /home/frappe/frappe-bench/apps/erpnext/erpnext/translations/bg.csv
# nano /home/frappe/frappe-bench/apps/frappe/frappe/translations/bg.csv



# Exit on error
set -e

# Clear cache for the site
echo "Clearing cache..."
bench --site erptest.ess.bg clear-cache || { echo "Cache clear failed"; exit 1; }

# Run migrations for the site
echo "Running migrations..."
bench --site erptest.ess.bg migrate || { echo "Migration failed"; exit 1; }

# Restart bench services
echo "Restarting bench..."
bench restart || { echo "Restart failed"; exit 1; }

echo "All operations completed successfully!"
