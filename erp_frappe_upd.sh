#!/bin/bash

# ERPNext Update Script
# This script safely updates ERPNext and Frappe while preserving custom translations
# Usage: ./erp_frapper_upd.sh [bench_path]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default bench path
BENCH_PATH="${1:-$(pwd)}"
BACKUP_DIR="$HOME/erpnext_update_backups_$(date +%Y%m%d_%H%M%S)"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if we're in a bench directory
    if [[ ! -f "$BENCH_PATH/apps/frappe/frappe/__init__.py" ]]; then
        log_error "Not a valid bench directory: $BENCH_PATH"
        log_error "Usage: $0 [bench_path]"
        exit 1
    fi
    
    # Check if bench command exists
    if ! command -v bench &> /dev/null; then
        log_error "bench command not found. Please install frappe-bench first."
        exit 1
    fi
    
    # Check if running as frappe user (recommended)
    if [[ "$USER" != "frappe" ]]; then
        log_warning "Not running as 'frappe' user. Current user: $USER"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    log_success "Backup directory created"
}

backup_translations() {
    log_info "Backing up custom translations..."
    
    # Backup frappe translations
    if [[ -f "$BENCH_PATH/apps/frappe/frappe/translations/bg.csv" ]]; then
        cp "$BENCH_PATH/apps/frappe/frappe/translations/bg.csv" "$BACKUP_DIR/frappe_bg_translations.csv"
        log_success "Frappe BG translations backed up"
    fi
    
    # Backup ERPNext translations
    if [[ -f "$BENCH_PATH/apps/erpnext/erpnext/translations/bg.csv" ]]; then
        cp "$BENCH_PATH/apps/erpnext/erpnext/translations/bg.csv" "$BACKUP_DIR/erpnext_bg_translations.csv"
        log_success "ERPNext BG translations backed up"
    fi
    
    # Backup any other translation files
    find "$BENCH_PATH/apps" -name "*.csv" -path "*/translations/*" -exec cp {} "$BACKUP_DIR/" \; 2>/dev/null || true
    
    # Create a list of all backed up files
    ls -la "$BACKUP_DIR" > "$BACKUP_DIR/backup_inventory.txt"
    log_success "All translation files backed up to $BACKUP_DIR"
}

get_current_versions() {
    log_info "Getting current versions..."
    cd "$BENCH_PATH"
    
    echo "Current versions:" > "$BACKUP_DIR/versions_before.txt"
    bench version >> "$BACKUP_DIR/versions_before.txt"
    
    # Display current versions
    bench version
}

check_uncommitted_changes() {
    log_info "Checking for uncommitted changes..."
    
    local has_changes=false
    
    # Check each app for uncommitted changes
    for app_dir in "$BENCH_PATH/apps"/*; do
        if [[ -d "$app_dir/.git" ]]; then
            app_name=$(basename "$app_dir")
            cd "$app_dir"
            
            if ! git diff --quiet || ! git diff --cached --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
                log_warning "App '$app_name' has uncommitted changes"
                git status --porcelain > "$BACKUP_DIR/${app_name}_git_status.txt"
                has_changes=true
                
                # Show the changes
                echo "Changes in $app_name:"
                git status --short
            fi
        fi
    done
    
    if [[ "$has_changes" == true ]]; then
        log_warning "Uncommitted changes found in some apps"
        return 1
    else
        log_success "No uncommitted changes found"
        return 0
    fi
}

stash_changes() {
    log_info "Stashing uncommitted changes..."
    
    for app_dir in "$BENCH_PATH/apps"/*; do
        if [[ -d "$app_dir/.git" ]]; then
            app_name=$(basename "$app_dir")
            cd "$app_dir"
            
            # Check if there are changes to stash
            if ! git diff --quiet || ! git diff --cached --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
                log_info "Stashing changes in $app_name..."
                
                # Add untracked files and stash everything
                git add -A
                git stash push -m "Auto-stash before ERPNext update $(date)"
                
                log_success "Changes stashed in $app_name"
            fi
        fi
    done
}

perform_update() {
    log_info "Starting ERPNext update..."
    cd "$BENCH_PATH"
    
    # Create site backup before update
    log_info "Creating site backup..."
    bench backup --with-files || log_warning "Backup failed, continuing with update"
    
    # Try regular update first
    log_info "Attempting regular update..."
    if bench update; then
        log_success "Regular update completed successfully"
        return 0
    else
        log_warning "Regular update failed, trying alternative methods..."
        
        # Try update with reset if regular update fails
        log_warning "Trying update with --reset flag..."
        read -p "This will discard any local changes permanently. Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bench update --reset
        else
            log_error "Update cancelled by user"
            return 1
        fi
    fi
}

restore_translations() {
    log_info "Restoring custom translations..."
    
    for app_dir in "$BENCH_PATH/apps"/*; do
        if [[ -d "$app_dir/.git" ]]; then
            app_name=$(basename "$app_dir")
            cd "$app_dir"
            
            # Try to restore stashed changes
            if git stash list | grep -q "Auto-stash before ERPNext update"; then
                log_info "Restoring stashed changes in $app_name..."
                if git stash pop; then
                    log_success "Stashed changes restored in $app_name"
                else
                    log_warning "Could not restore stashed changes in $app_name - there might be conflicts"
                    log_info "You can manually resolve conflicts later with: cd $app_dir && git stash pop"
                fi
            fi
        fi
    done
    
    # If stash restore failed, restore from backup files
    if [[ -f "$BACKUP_DIR/frappe_bg_translations.csv" ]]; then
        cp "$BACKUP_DIR/frappe_bg_translations.csv" "$BENCH_PATH/apps/frappe/frappe/translations/bg.csv"
        log_info "Frappe BG translations restored from backup"
    fi
    
    if [[ -f "$BACKUP_DIR/erpnext_bg_translations.csv" ]]; then
        cp "$BACKUP_DIR/erpnext_bg_translations.csv" "$BENCH_PATH/apps/erpnext/erpnext/translations/bg.csv"
        log_info "ERPNext BG translations restored from backup"
    fi
}

build_and_restart() {
    log_info "Building assets and restarting services..."
    cd "$BENCH_PATH"
    
    # Build assets
    if bench build; then
        log_success "Assets built successfully"
    else
        log_warning "Asset build failed, but continuing..."
    fi
    
    # Restart services
    if bench restart; then
        log_success "Services restarted successfully"
    else
        log_warning "Service restart failed, you may need to restart manually"
        log_info "Try: bench restart or sudo supervisorctl restart all"
    fi
}

verify_update() {
    log_info "Verifying update..."
    cd "$BENCH_PATH"
    
    # Get new versions
    echo "Versions after update:" > "$BACKUP_DIR/versions_after.txt"
    bench version >> "$BACKUP_DIR/versions_after.txt"
    
    # Display new versions
    log_info "New versions:"
    bench version
    
    # Compare versions
    if diff "$BACKUP_DIR/versions_before.txt" "$BACKUP_DIR/versions_after.txt" > /dev/null; then
        log_warning "No version changes detected"
    else
        log_success "Version changes detected:"
        diff "$BACKUP_DIR/versions_before.txt" "$BACKUP_DIR/versions_after.txt" || true
    fi
}

cleanup_and_summary() {
    log_info "Update process completed!"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Summary of files backed up:"
    cat "$BACKUP_DIR/backup_inventory.txt"
    
    log_success "ERPNext update script finished successfully"
    log_info "Please test your system to ensure everything is working correctly"
    log_info "If you encounter issues, your backups are available in: $BACKUP_DIR"
}

# Main execution
main() {
    echo "=================================================="
    echo "          ERPNext Update Script v1.0             "
    echo "=================================================="
    echo
    
    check_prerequisites
    create_backup_directory
    get_current_versions
    backup_translations
    
    if ! check_uncommitted_changes; then
        log_info "Uncommitted changes found. Options:"
        echo "1. Stash changes automatically (recommended)"
        echo "2. Exit and handle manually"
        read -p "Choose option (1/2): " -n 1 -r
        echo
        
        case $REPLY in
            1)
                stash_changes
                ;;
            2)
                log_info "Exiting. Please handle uncommitted changes manually and run the script again."
                exit 0
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    fi
    
    perform_update
    restore_translations
    build_and_restart
    verify_update
    cleanup_and_summary
}

# Run main function
main "$@"
