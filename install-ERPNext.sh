#!/bin/bash
# ERPNext v15 One-Click Installation Script for Ubuntu 24.04
# This script automates the complete installation of ERPNext v15 on a fresh Ubuntu 24.04 system
# Author: GuN®! Script is generated based on community guides
# Version: 1.6 - Created: June 25, 2025 12:42 EEST (Europe/Sofia)
# Fixed nginx log format issue, systemd configuration prompt issue, HRMS = No by default

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (modify these as needed)
FRAPPE_USER="frappe"
SITE_NAME="erptest.local"
MYSQL_ROOT_PASSWORD=""  # Will be prompted if not set
NODE_VERSION="18"
ERPNEXT_BRANCH="version-15"
INSTALL_HRMS="no"  # Set to "yes" if you want HRMS
PRODUCTION_SETUP="yes"  # Set to "no" for development setup only

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root user for security reasons."
        print_status "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if [[ $(lsb_release -rs) != "24.04" ]]; then
        print_warning "This script is optimized for Ubuntu 24.04. You're running $(lsb_release -rs)."
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    sudo apt-get update -y
    sudo apt-get upgrade -y
    print_success "System packages updated successfully"
}

# Function to create frappe user
create_frappe_user() {
    print_status "Creating frappe user..."
    if id "$FRAPPE_USER" &>/dev/null; then
        print_warning "User $FRAPPE_USER already exists"
    else
        sudo adduser --disabled-password --gecos "" $FRAPPE_USER
        sudo usermod -aG sudo $FRAPPE_USER
        print_success "User $FRAPPE_USER created successfully"
    fi
}

# Function to install basic packages
install_basic_packages() {
    print_status "Installing basic packages..."
    sudo apt-get install -y \
        git \
        python3-dev \
        python3.12-dev \
        python3-setuptools \
        python3-pip \
        python3.12-venv \
        python3-full \
        pipx \
        software-properties-common \
        libmysqlclient-dev \
        redis-server \
        xvfb \
        libfontconfig \
        wkhtmltopdf \
        curl \
        npm \
        build-essential \
        gettext \
        ansible \
        expect
    print_success "Basic packages installed successfully"
}

# Function to install and configure Redis
configure_redis() {
    print_status "Configuring Redis..."
    
    # Stop Redis service
    sudo systemctl stop redis-server
    
    # Configure Redis
    sudo tee /etc/redis/redis.conf > /dev/null <<EOF
# Redis configuration for ERPNext
bind 127.0.0.1
port 6379
timeout 0
save 900 1
save 300 10
save 60 10000
rdbcompression yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory-policy allkeys-lru
maxmemory 256mb
EOF

    # Set proper permissions
    sudo chown redis:redis /etc/redis/redis.conf
    sudo chmod 640 /etc/redis/redis.conf
    
    # Start and enable Redis
    sudo systemctl start redis-server
    sudo systemctl enable redis-server
    
    # Test Redis connection
    sleep 2
    if redis-cli ping | grep -q "PONG"; then
        print_success "Redis configured and running successfully"
    else
        print_error "Redis configuration failed"
        exit 1
    fi
}

# Function to install and configure MariaDB
install_configure_mariadb() {
    print_status "Installing MariaDB..."
    sudo apt install -y mariadb-server mariadb-client
    
    print_status "Configuring MariaDB..."
    
    # Get MySQL root password if not set
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        while true; do
            read -s -p "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
            echo
            read -s -p "Confirm MySQL root password: " MYSQL_ROOT_PASSWORD_CONFIRM
            echo
            if [[ "$MYSQL_ROOT_PASSWORD" == "$MYSQL_ROOT_PASSWORD_CONFIRM" ]]; then
                break
            else
                print_error "Passwords do not match. Please try again."
            fi
        done
    fi

    # Secure MariaDB installation
    sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';"
    sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE User='';"
    sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE IF EXISTS test;"
    sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

    # Configure MySQL settings
    print_status "Configuring MySQL settings..."
    sudo tee -a /etc/mysql/my.cnf > /dev/null <<EOF

[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
innodb-file-format=barracuda
innodb-file-per-table=1
innodb-large-prefix=1

[mysql]
default-character-set = utf8mb4
EOF

    sudo service mysql restart
    print_success "MariaDB installed and configured successfully"
}

# Function to install Node.js via NVM
install_nodejs() {
    print_status "Installing Node.js..."
    
    # Install NVM for frappe user
    sudo -u $FRAPPE_USER bash << 'EOF'
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
EOF
    
    # Install Node.js for frappe user
    sudo -u $FRAPPE_USER bash << EOF
export NVM_DIR="/home/$FRAPPE_USER/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
npm install -g yarn
# Install additional Node.js build tools
npm install -g @rollup/plugin-json
EOF
    
    print_success "Node.js and Yarn installed successfully"
}

# Function to install Frappe Bench
install_frappe_bench() {
    print_status "Installing Frappe Bench..."
    
    # Install frappe-bench using pip with break-system-packages for Ubuntu 24.04
    sudo -H pip3 install frappe-bench --break-system-packages
    
    print_success "Frappe Bench installed successfully"
}

# Function to initialize bench as frappe user
initialize_bench() {
    print_status "Initializing Frappe Bench..."
    
    # Switch to frappe user and initialize bench
    sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER
export NVM_DIR="/home/$FRAPPE_USER/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
nvm use $NODE_VERSION

# Initialize bench
bench init frappe-bench --frappe-branch $ERPNEXT_BRANCH

# Configure Redis in common_site_config.json
cd frappe-bench
cat > sites/common_site_config.json << 'EOL'
{
  "redis_cache": "redis://127.0.0.1:6379",
  "redis_queue": "redis://127.0.0.1:6379",
  "redis_socketio": "redis://127.0.0.1:6379",
  "socketio_port": 9000,
  "background_workers": 1,
  "shallow_clone": true,
  "restart_supervisor_on_update": false,
  "restart_systemd_on_update": false,
  "serve_default_site": true,
  "reopen_log_files": true,
  "auto_update": false
}
EOL
EOF

    # Set proper permissions
    sudo chmod -R o+rx /home/$FRAPPE_USER/
    
    print_success "Frappe Bench initialized successfully with Redis configuration"
}

# Function to create site and install apps
create_site_install_apps() {
    print_status "Creating site and installing ERPNext..."
    
    sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER/frappe-bench
export NVM_DIR="/home/$FRAPPE_USER/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && \. "\$NVM_DIR/bash_completion"
nvm use $NODE_VERSION

# Ensure Redis is accessible
redis-cli ping

# Create new site with database connection
bench new-site $SITE_NAME --admin-password admin --mariadb-root-password $MYSQL_ROOT_PASSWORD

# Get required apps
bench get-app payments
bench get-app --branch $ERPNEXT_BRANCH erpnext

# Install ERPNext
bench --site $SITE_NAME install-app erpnext

# Install HRMS if requested
if [[ "$INSTALL_HRMS" == "yes" ]]; then
    echo "Getting HRMS app..."
    bench get-app hrms
    
    echo "Installing HRMS app..."
    # Build assets first to avoid build errors
    bench build --app hrms
    
    # Install HRMS with retry mechanism
    for i in {1..3}; do
        if bench --site $SITE_NAME install-app hrms; then
            echo "HRMS installed successfully"
            break
        else
            echo "HRMS installation attempt \$i failed, retrying in 10 seconds..."
            sleep 10
            # Clear any cache issues
            bench --site $SITE_NAME clear-cache
            bench --site $SITE_NAME clear-website-cache
            # Try rebuilding assets
            bench build --app hrms
        fi
        
        if [[ \$i -eq 3 ]]; then
            echo "HRMS installation failed after 3 attempts. You can try installing it manually later with:"
            echo "bench --site $SITE_NAME install-app hrms"
        fi
    done
else
    echo "HRMS installation skipped (set INSTALL_HRMS='yes' to install)"
fi
EOF

    print_success "Site created and ERPNext installed successfully"
}

# Function to fix nginx configuration
fix_nginx_config() {
    print_status "Fixing nginx configuration..."
    
    # Add the missing log format to nginx.conf if it doesn't exist
    if ! grep -q "log_format main" /etc/nginx/nginx.conf; then
        print_status "Adding missing 'main' log format to nginx.conf..."
        sudo sed -i '/http {/a\\n\t# ERPNext log format\n\tlog_format main '\''$remote_addr - $remote_user [$time_local] "$request" '\''\n\t\t\t'\''$status $body_bytes_sent "$http_referer" '\''\n\t\t\t'\''"$http_user_agent" "$http_x_forwarded_for"'\'';' /etc/nginx/nginx.conf
    fi
    
    print_success "Nginx configuration fixed"
}

# Function to setup production environment with automatic confirmation
setup_production() {
    if [[ "$PRODUCTION_SETUP" == "yes" ]]; then
        print_status "Setting up production environment..."
        
        # Install additional packages for production
        sudo apt update
        sudo apt install -y nginx supervisor fail2ban
        
        # Stop any conflicting services
        sudo systemctl stop apache2 2>/dev/null || true
        
        # Fix nginx configuration first
        fix_nginx_config
        
        # Enable scheduler and disable maintenance mode
        sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER/frappe-bench
# Enable scheduler
bench --site $SITE_NAME enable-scheduler
# Disable maintenance mode
bench --site $SITE_NAME set-maintenance-mode off
EOF

        # Setup production configuration manually to avoid prompts
        print_status "Setting up production configuration manually..."
        
        # Create nginx configuration
        sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER/frappe-bench
bench setup nginx --yes
EOF

        # Fix the log format issue in the generated nginx config
        sudo sed -i 's/access_log.*main;/access_log \/var\/log\/nginx\/access.log combined;/g' /home/$FRAPPE_USER/frappe-bench/config/nginx.conf
        
        # Copy nginx configuration
        sudo cp /home/$FRAPPE_USER/frappe-bench/config/nginx.conf /etc/nginx/sites-available/frappe-bench
        sudo ln -sf /etc/nginx/sites-available/frappe-bench /etc/nginx/sites-enabled/frappe-bench
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test nginx configuration
        if sudo nginx -t; then
            print_success "Nginx configuration is valid"
        else
            print_error "Nginx configuration test failed"
            exit 1
        fi
        
        # Create supervisor configuration
        sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER/frappe-bench
bench setup supervisor --yes
sudo cp config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf
EOF

        # Setup systemd services with automatic yes confirmation
        print_status "Setting up systemd services..."
        sudo -u $FRAPPE_USER bash << EOF
cd /home/$FRAPPE_USER/frappe-bench
# Use expect to automatically answer yes to systemd prompt
expect << 'EOD'
spawn bench setup systemd
expect "Do you want to continue? \[y/N\]:" { send "y\r" }
expect eof
EOD
EOF

        # Start and enable services
        sudo supervisorctl reread
        sudo supervisorctl update
        sudo supervisorctl start all
        sudo systemctl enable supervisor
        sudo systemctl enable nginx
        sudo systemctl restart nginx
        
        # Verify nginx is running
        if sudo systemctl is-active --quiet nginx; then
            print_success "Nginx started successfully"
        else
            print_error "Failed to start nginx"
            sudo systemctl status nginx
            exit 1
        fi
        
        # Setup firewall
        sudo ufw allow 22,25,143,80,443,3306,3022,8000/tcp
        echo "y" | sudo ufw enable
        
        print_success "Production environment setup completed"
    fi
}

# Function to verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Check Redis
    if redis-cli ping | grep -q "PONG"; then
        print_success "Redis is running correctly"
    else
        print_warning "Redis may not be running properly"
    fi
    
    # Check MariaDB
    if sudo mysql -u root -p$MYSQL_ROOT_PASSWORD -e "SELECT 1;" > /dev/null 2>&1; then
        print_success "MariaDB is accessible"
    else
        print_warning "MariaDB connection issues detected"
    fi
    
    # Check if site exists
    if sudo -u $FRAPPE_USER bash -c "cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME show-config" > /dev/null 2>&1; then
        print_success "Site configuration is valid"
    else
        print_warning "Site configuration issues detected"
    fi
    
    # Check Redis configuration in site config
    if sudo -u $FRAPPE_USER bash -c "cd /home/$FRAPPE_USER/frappe-bench && grep -q 'redis_cache' sites/common_site_config.json"; then
        print_success "Redis configuration is properly set"
    else
        print_warning "Redis configuration may be missing"
    fi
    
    # Check nginx configuration if production setup
    if [[ "$PRODUCTION_SETUP" == "yes" ]]; then
        if sudo nginx -t > /dev/null 2>&1; then
            print_success "Nginx configuration is valid"
        else
            print_warning "Nginx configuration has issues"
        fi
    fi
}

# Function to display final information
display_final_info() {
    print_success "ERPNext v15 installation completed successfully!"
    echo
    print_status "Installation Summary:"
    echo "  - Frappe User: $FRAPPE_USER"
    echo "  - Site Name: $SITE_NAME"
    echo "  - ERPNext Branch: $ERPNEXT_BRANCH"
    echo "  - HRMS Installed: $INSTALL_HRMS"
    echo "  - Production Setup: $PRODUCTION_SETUP"
    echo "  - Script Version: 1.6"
    echo "  - Created: June 25, 2025 12:42 EEST (Europe/Sofia)"
    echo
    
    if [[ "$PRODUCTION_SETUP" == "yes" ]]; then
        print_status "Access your ERPNext installation at:"
        echo "  - URL: http://$(hostname -I | awk '{print $1}')"
        echo "  - OR: http://$SITE_NAME (if DNS configured)"
        echo "  - Username: Administrator"
        echo "  - Password: admin"
        echo
        print_status "Production services status:"
        echo "  - Nginx: $(systemctl is-active nginx)"
        echo "  - Supervisor: $(systemctl is-active supervisor)"
        echo "  - Redis: $(systemctl is-active redis-server)"
        echo "  - MariaDB: $(systemctl is-active mariadb)"
    else
        print_status "To start ERPNext in development mode:"
        echo "  sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench start'"
        echo "  Then access: http://$(hostname -I | awk '{print $1}'):8000"
        echo "  OR: http://$SITE_NAME:8000 (if DNS configured)"
    fi
    
    echo
    print_status "Useful commands:"
    echo "  - Start bench: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench start'"
    echo "  - Restart bench: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench restart'"
    echo "  - Update ERPNext: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench update'"
    echo "  - Access bench console: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME console'"
    echo "  - Check Redis: redis-cli ping"
    echo "  - View logs: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME logs'"
    echo "  - Clear cache: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME clear-cache'"
    echo "  - Check nginx status: sudo systemctl status nginx"
    echo "  - Check supervisor status: sudo supervisorctl status"
    
    echo
    print_status "Configuration files:"
    echo "  - Redis config: /etc/redis/redis.conf"
    echo "  - Site config: /home/$FRAPPE_USER/frappe-bench/sites/common_site_config.json"
    echo "  - Site specific config: /home/$FRAPPE_USER/frappe-bench/sites/$SITE_NAME/site_config.json"
    echo "  - Nginx config: /etc/nginx/sites-available/frappe-bench"
    echo "  - Supervisor config: /etc/supervisor/conf.d/frappe-bench.conf"
    
    if [[ "$INSTALL_HRMS" == "no" ]]; then
        echo
        print_status "To install HRMS later, run these commands:"
        echo "  sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench get-app hrms'"
        echo "  sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME install-app hrms'"
    fi
    
    echo
    print_status "Troubleshooting:"
    echo "  - If nginx fails: sudo nginx -t && sudo systemctl restart nginx"
    echo "  - If services fail: sudo supervisorctl restart all"
    echo "  - View nginx errors: sudo tail -f /var/log/nginx/error.log"
    echo "  - View bench logs: sudo -u $FRAPPE_USER bash -c 'cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME logs'"
}

# Function to handle cleanup on error
cleanup_on_error() {
    print_error "Installation failed. Performing cleanup..."
    # Stop any running bench processes
    sudo pkill -f "bench start" 2>/dev/null || true
    exit 1
}

# Main installation function
main() {
    echo "======================================"
    echo "ERPNext v15 Installation Script"
    echo "Ubuntu 24.04 One-Click Installer"
    echo "Version: 1.6 - Created: June 25, 2025 12:42 EEST (Europe/Sofia)"
    echo "======================================"
    echo
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR
    
    # Pre-installation checks
    check_root
    check_ubuntu_version
    
    # Confirm installation
    print_status "This script will install ERPNext v15 with the following configuration:"
    echo "  - Frappe User: $FRAPPE_USER"
    echo "  - Site Name: $SITE_NAME"
    echo "  - Install HRMS: $INSTALL_HRMS"
    echo "  - Production Setup: $PRODUCTION_SETUP"
    echo
    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled by user"
        exit 0
    fi
    
    # Installation steps
    update_system
    create_frappe_user
    install_basic_packages
    configure_redis
    install_configure_mariadb
    install_nodejs
    install_frappe_bench
    initialize_bench
    create_site_install_apps
    setup_production
    verify_installation
    
    # Display final information
    display_final_info
}

# Run main function
main "$@"
