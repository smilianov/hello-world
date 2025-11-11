#!/usr/bin/env bash
# traccar_tools.sh – interactive installer/upgrade/backup utility for Traccar
# Works on Debian/Ubuntu-like systems.

set -euo pipefail

#-------------------------------#
#            CONFIG             #
#-------------------------------#
TRACCAR_SERVICE="traccar.service"
TRACCAR_DIR="/opt/traccar"
SYSTEMD_PATH="/etc/systemd/system"
BACKUP_DIR="/root/backup"
MYSQL_USER="${MYSQL_USER:-root}"      # allow override via env
MYSQL_PASS="${MYSQL_PASS:-root}"      # allow override via env
MYSQL_BACKUP_DIR="/root/mysql_backup"
DAYS_TO_KEEP="${DAYS_TO_KEEP:-3}"
COMPRESS_DB="${COMPRESS_DB:-1}"       # 1=gzip, 0=plain
LOG_FILE="/var/log/traccar-tools.log" # keep our logs separate from Traccar app logs

# Do not edit below unless you know what you're doing
LATEST_VERSION=""
LATEST_URL=""
TMPDIR="$(mktemp -d -t traccar-tools.XXXXXXXX)"

# Colors
RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;36m"; GREEN="\033[0;32m"; NORMAL="\033[0m"

#-------------------------------#
#           UTILITIES           #
#-------------------------------#

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        echo -e "${RED}This script must be run as root (or with sudo).${NORMAL}"
        exit 1
    fi
}

ensure_dirs() {
    mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR" "$MYSQL_BACKUP_DIR"
    chmod 700 "$BACKUP_DIR" "$MYSQL_BACKUP_DIR" || true
}

cleanup() {
    rm -rf "$TMPDIR" 2>/dev/null || true
}
trap cleanup EXIT

log() {
    local msg="$1"
    local entry
    entry="$(date '+%Y-%m-%d %H:%M:%S') - $msg"
    echo -e "$entry" | tee -a "$LOG_FILE" >&2
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_deps() {
    local need=("curl" "unzip" "wget" "systemctl")
    local missing=()
    for c in "${need[@]}"; do have_cmd "$c" || missing+=("$c"); done
    if ((${#missing[@]})); then
        log "Installing missing dependencies: ${missing[*]}"
        apt-get update -y
        apt-get install -y "${missing[@]}"
    fi
    # MySQL tools are optional until used; we’ll check on demand.
}

prompt_confirm() {
    local msg="$1"
    while true; do
        read -rp "$msg [y/n]: " yn
        case "$yn" in
            [Yy]*) log "User confirmed: $msg"; return 0;;
            [Nn]*) log "User declined: $msg"; return 1;;
            *) echo "Please answer y or n.";;
        esac
    done
}

print_menu() {
    echo -e "${BLUE}--- Traccar Tools Menu ---${NORMAL}"
    echo "1) Uninstall Traccar"
    echo "2) Install Traccar"
    echo "3) Upgrade Traccar"
    echo "4) Restart Traccar"
    echo "5) Show tool log"
    echo "6) Show service status"
    echo "7) Check latest Traccar release"
    echo "8) Backup MySQL (traccar DB)"
    echo "9) Import MySQL (traccar DB)"
    echo "10) Install MySQL server (and configure Traccar)"
    echo -e "11) ${RED}Reset MySQL server (DANGER!)${NORMAL}"
    echo "x) Exit"
}

#-------------------------------#
#        TRACCAR CONFIG         #
#-------------------------------#

update_traccar_config() {
    log "Updating Traccar config at $TRACCAR_DIR/conf/traccar.xml"
    install -d -m 0755 "$TRACCAR_DIR/conf"
    cat > "$TRACCAR_DIR/conf/traccar.xml" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE properties SYSTEM 'http://java.sun.com/dtd/properties.dtd'>
<properties>
    <entry key='config.default'>./conf/default.xml</entry>
    <!-- Database connection -->
    <entry key='database.driver'>com.mysql.cj.jdbc.Driver</entry>
    <entry key='database.url'>jdbc:mysql://127.0.0.1:3306/traccar?useSSL=false&characterEncoding=UTF-8</entry>
    <entry key='database.user'>${MYSQL_USER}</entry>
    <entry key='database.password'>${MYSQL_PASS}</entry>
</properties>
EOF
    log "Traccar config updated"
}

#-------------------------------#
#   FETCH LATEST TRACCAR URL    #
#-------------------------------#

gen_latest_url() {
    log "Fetching latest Traccar release metadata from GitHub"
    local json url name
    # Try with jq if present, otherwise use a robust grep/sed fallback
    if have_cmd jq; then
        json="$(curl -fsSL https://api.github.com/repos/traccar/traccar/releases/latest)"
        url="$(echo "$json" | jq -r '.assets[]?.browser_download_url | select(test("traccar-linux-64-.*\\.zip$"))' | head -n1)"
    else
        json="$(curl -fsSL https://api.github.com/repos/traccar/traccar/releases/latest || true)"
        url="$(echo "$json" | grep -oE '"browser_download_url": *"[^"]+"' \
              | sed -E 's/.*"([^"]+)".*/\1/' \
              | grep -E 'traccar-linux-64-.*\.zip$' \
              | head -n1 || true)"
    fi
    if [[ -z "${url:-}" ]]; then
        log "Failed to determine download URL for latest linux-64 zip"
        return 1
    fi
    name="$(basename "$url")"             # traccar-linux-64-x.y.z.zip
    name="${name%.zip}"
    LATEST_VERSION="${name#traccar-linux-64-}"
    LATEST_URL="$url"
    log "Latest Traccar version: $LATEST_VERSION ($LATEST_URL)"
}

download_traccar() {
    if ! gen_latest_url; then
        log "Could not detect latest Traccar URL"
        return 1
    fi
    if prompt_confirm "Download version $LATEST_VERSION?"; then
        local out="$TMPDIR/traccar.zip"
        wget -q "$LATEST_URL" -O "$out"
        log "Downloaded: $out"
        echo "$out"
        return 0
    else
        log "Download skipped by user"
        return 1
    fi
}

#-------------------------------#
#         INSTALL / UPGRADE     #
#-------------------------------#

install_traccar() {
    local zipfile
    zipfile="$(download_traccar)" || return 1
    unzip -q "$zipfile" -d "$TMPDIR"
    chmod +x "$TMPDIR/traccar.run"
    # If an old service exists, stop it to avoid port conflicts during install.
    systemctl stop "$TRACCAR_SERVICE" 2>/dev/null || true
    "$TMPDIR/traccar.run" <<<'y' >/dev/null 2>&1 || true
    systemctl daemon-reload
    systemctl enable "$TRACCAR_SERVICE" >/dev/null 2>&1 || true
    systemctl start "$TRACCAR_SERVICE"
    log "Installed Traccar $LATEST_VERSION"
    install -d -m 0755 "$TRACCAR_DIR"
    echo "$LATEST_VERSION" > "$TRACCAR_DIR/version.txt"
    log "Wrote version to $TRACCAR_DIR/version.txt"
}

upgrade_traccar() {
    local zipfile
    zipfile="$(download_traccar)" || return 1

    install -d -m 0755 "$BACKUP_DIR" "$BACKUP_DIR/conf"
    log "Stopping $TRACCAR_SERVICE"
    systemctl stop "$TRACCAR_SERVICE" || true

    # Back up systemd unit, config, and H2 DB (if present)
    [[ -f "$SYSTEMD_PATH/$TRACCAR_SERVICE" ]] && cp -a "$SYSTEMD_PATH/$TRACCAR_SERVICE" "$BACKUP_DIR/"
    if compgen -G "$TRACCAR_DIR/conf/*.xml" > /dev/null; then
        cp -a "$TRACCAR_DIR/conf"/*.xml "$BACKUP_DIR/conf/"
    fi
    if compgen -G "$TRACCAR_DIR/data/*.db" > /dev/null; then
        cp -a "$TRACCAR_DIR/data"/*.db "$BACKUP_DIR/"
    fi

    systemctl disable "$TRACCAR_SERVICE" >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_PATH/$TRACCAR_SERVICE"
    systemctl daemon-reload

    rm -rf "$TRACCAR_DIR"

    unzip -q "$zipfile" -d "$TMPDIR"
    chmod +x "$TMPDIR/traccar.run"
    "$TMPDIR/traccar.run" <<<'y' >/dev/null 2>&1 || true

    # Restore unit and configs if we had them
    if [[ -f "$BACKUP_DIR/$TRACCAR_SERVICE" ]]; then
        cp -a "$BACKUP_DIR/$TRACCAR_SERVICE" "$SYSTEMD_PATH/"
    fi
    install -d -m 0755 "$TRACCAR_DIR/conf" "$TRACCAR_DIR/data"
    if compgen -G "$BACKUP_DIR/conf/*.xml" > /dev/null; then
        cp -a "$BACKUP_DIR/conf"/*.xml "$TRACCAR_DIR/conf/"
    fi
    if compgen -G "$BACKUP_DIR/*.db" > /dev/null; then
        cp -a "$BACKUP_DIR"/*.db "$TRACCAR_DIR/data/"
    fi

    systemctl daemon-reload
    systemctl enable "$TRACCAR_SERVICE" >/dev/null 2>&1 || true
    systemctl start "$TRACCAR_SERVICE"

    log "Upgraded Traccar to $LATEST_VERSION"
    echo "$LATEST_VERSION" > "$TRACCAR_DIR/version.txt"
    log "Wrote version to $TRACCAR_DIR/version.txt"
}

uninstall_traccar() {
    if prompt_confirm "Are you sure you want to uninstall Traccar and delete all data?"; then
        log "Uninstalling Traccar ..."
        systemctl stop "$TRACCAR_SERVICE" || true
        systemctl disable "$TRACCAR_SERVICE" >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_PATH/$TRACCAR_SERVICE"
        systemctl daemon-reload
        rm -rf "$TRACCAR_DIR"
        log "Traccar uninstalled"
    else
        log "Uninstallation cancelled by user"
        echo "Uninstallation cancelled."
        return 1
    fi
}

restart_traccar() { systemctl restart "$TRACCAR_SERVICE"; }

show_log() {
    # Show this tool's log (not the Traccar tracker log)
    tail -n 100 "$LOG_FILE" || true
}

show_status() {
    systemctl status "$TRACCAR_SERVICE" --no-pager || true
}

check_latest() {
    if gen_latest_url; then
        echo "Latest Traccar: $LATEST_VERSION"
        echo "URL: $LATEST_URL"
    else
        echo "Could not fetch latest release info."
    fi
}

#-------------------------------#
#        MYSQL OPERATIONS       #
#-------------------------------#

ensure_mysql_tools() {
    local need=("mysql" "mysqldump")
    local missing=()
    for c in "${need[@]}"; do have_cmd "$c" || missing+=("$c"); done
    if ((${#missing[@]})); then
        log "Installing MySQL client tools: ${missing[*]}"
        apt-get update -y
        apt-get install -y mysql-client
    fi
}

backup_mysql() {
    ensure_mysql_tools
    log "Starting MySQL backup to $MYSQL_BACKUP_DIR"
    install -d -m 0700 "$MYSQL_BACKUP_DIR"
    systemctl stop "$TRACCAR_SERVICE" || true

    local date_str=""; date_str="$(date +%Y-%m-%d)"
    # Only back up the 'traccar' database to avoid huge dumps of everything.
    if [[ "$COMPRESS_DB" -eq 1 ]]; then
        mysqldump --single-transaction --routines --triggers \
            -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar \
            | gzip -c > "$MYSQL_BACKUP_DIR/${date_str}-traccar.sql.gz"
    else
        mysqldump --single-transaction --routines --triggers \
            -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar \
            > "$MYSQL_BACKUP_DIR/${date_str}-traccar.sql"
    fi
    log "Backed up 'traccar' database"
    find "$MYSQL_BACKUP_DIR" -type f -mtime +$DAYS_TO_KEEP -delete || true

    systemctl start "$TRACCAR_SERVICE" || true
    log "MySQL backup completed"
}

import_mysql() {
    ensure_mysql_tools
    if prompt_confirm "Import a Traccar MySQL backup into database 'traccar'?"; then
        systemctl stop "$TRACCAR_SERVICE" || true
        mapfile -t backups < <(ls -1t "$MYSQL_BACKUP_DIR"/*traccar.sql* 2>/dev/null || true)
        if ((${#backups[@]} == 0)); then
            log "No backups found"
            echo "No backup files found in $MYSQL_BACKUP_DIR"
            systemctl start "$TRACCAR_SERVICE" || true
            return 1
        fi
        echo "Available backups:"
        for i in "${!backups[@]}"; do printf "%3d) %s\n" $((i+1)) "${backups[i]}"; done
        read -rp "Select backup: " sel
        if [[ ! "$sel" =~ ^[0-9]+$ || "$sel" -lt 1 || "$sel" -gt ${#backups[@]} ]]; then
            echo "Invalid selection"
            systemctl start "$TRACCAR_SERVICE" || true
            return 1
        fi
        local file="${backups[$((sel-1))]}"
        log "Importing $file into 'traccar' DB"
        if [[ "$file" == *.gz ]]; then
            gunzip -c "$file" | mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar
        else
            mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" traccar < "$file"
        fi
        systemctl start "$TRACCAR_SERVICE" || true
        log "Import completed"
    fi
}

install_mysql_server() {
    if prompt_confirm "Install MySQL server and configure for Traccar?"; then
        log "Installing MySQL server"
        systemctl stop "$TRACCAR_SERVICE" || true
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
        # Set root password + permissive root for localhost
        mysql -u root --execute="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}'; FLUSH PRIVILEGES;"
        mysql -u root -p"${MYSQL_PASS}" --execute="CREATE DATABASE IF NOT EXISTS traccar; GRANT ALL ON traccar.* TO 'root'@'localhost'; FLUSH PRIVILEGES;"
        update_traccar_config
        systemctl enable mysql >/dev/null 2>&1 || true
        systemctl start mysql
        systemctl start "$TRACCAR_SERVICE" || true
        log "MySQL installed and configured"
    fi
}

reset_mysql_server() {
    if prompt_confirm "Reset MySQL server (remove and reinstall)? All databases will be lost."; then
        log "Resetting MySQL server"
        systemctl stop "$TRACCAR_SERVICE" || true
        systemctl stop mysql || true
        apt-get -y purge mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* || true
        apt-get -y autoremove || true
        apt-get -y autoclean || true
        apt-get update -y
        DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
        mysql -u root --execute="ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}'; FLUSH PRIVILEGES;"
        mysql -u root -p"${MYSQL_PASS}" --execute="CREATE DATABASE IF NOT EXISTS traccar; GRANT ALL ON traccar.* TO 'root'@'localhost'; FLUSH PRIVILEGES;"
        update_traccar_config
        systemctl enable mysql >/dev/null 2>&1 || true
        systemctl start mysql
        systemctl start "$TRACCAR_SERVICE" || true
        log "MySQL reset and configured"
    fi
}

#-------------------------------#
#             MAIN              #
#-------------------------------#

main() {
    require_root
    ensure_dirs
    ensure_deps
    log "Starting traccar_tools"
    while true; do
        print_menu
        read -rp "Choose option: " opt
        case "$opt" in
            1) uninstall_traccar      ;;
            2) install_traccar        ;;
            3) upgrade_traccar        ;;
            4) restart_traccar        ;;
            5) show_log               ;;
            6) show_status            ;;
            7) check_latest           ;;
            8) backup_mysql           ;;
            9) import_mysql           ;;
            10) install_mysql_server  ;;
            11) reset_mysql_server    ;;
            x) log "Exiting script"; echo "Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NORMAL}" ;;
        esac
    done
}

main
