#!/bin/bash

set -e

echo "🗑️  Uninstalling Go MTA Relay System"
echo "===================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MTA_DIR="/opt/go-mta"
QUEUE_DIR="/var/mailqueue"
USERS_FILE="/root/users.txt"
LOG_DIR="/var/log"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root${NC}"
   exit 1
fi

# Confirmation prompt
confirm_uninstall() {
    echo -e "${YELLOW}⚠️  WARNING: This will completely remove the MTA relay system!${NC}"
    echo ""
    echo "This will remove:"
    echo "  - MTA server and queue processor"
    echo "  - Systemd services"
    echo "  - SSL certificates (optional)"
    echo "  - Queue directory and emails"
    echo "  - Log files"
    echo "  - Configuration files"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ $confirm != "yes" ]]; then
        echo -e "${YELLOW}Uninstallation cancelled.${NC}"
        exit 0
    fi
}

# Stop and disable services
stop_services() {
    echo -e "${YELLOW}[+] Stopping and disabling services...${NC}"
    
    # Stop services
    if systemctl is-active --quiet mta-server; then
        systemctl stop mta-server
        echo -e "${GREEN}[+] MTA Server stopped${NC}"
    fi
    
    if systemctl is-active --quiet mta-queue; then
        systemctl stop mta-queue
        echo -e "${GREEN}[+] MTA Queue stopped${NC}"
    fi
    
    # Disable services
    if systemctl is-enabled --quiet mta-server; then
        systemctl disable mta-server
        echo -e "${GREEN}[+] MTA Server disabled${NC}"
    fi
    
    if systemctl is-enabled --quiet mta-queue; then
        systemctl disable mta-queue
        echo -e "${GREEN}[+] MTA Queue disabled${NC}"
    fi
    
    # Reload systemd
    systemctl daemon-reload
}

# Remove systemd service files
remove_services() {
    echo -e "${YELLOW}[+] Removing systemd service files...${NC}"
    
    if [ -f "/etc/systemd/system/mta-server.service" ]; then
        rm -f /etc/systemd/system/mta-server.service
        echo -e "${GREEN}[+] Removed mta-server.service${NC}"
    fi
    
    if [ -f "/etc/systemd/system/mta-queue.service" ]; then
        rm -f /etc/systemd/system/mta-queue.service
        echo -e "${GREEN}[+] Removed mta-queue.service${NC}"
    fi
    
    # Reload systemd
    systemctl daemon-reload
}

# Remove MTA binaries and files
remove_mta_files() {
    echo -e "${YELLOW}[+] Removing MTA files...${NC}"
    
    if [ -d "$MTA_DIR" ]; then
        rm -rf "$MTA_DIR"
        echo -e "${GREEN}[+] Removed MTA directory: $MTA_DIR${NC}"
    fi
    
    # Remove binaries from /usr/local/bin if they exist
    if [ -f "/usr/local/bin/mta-server" ]; then
        rm -f /usr/local/bin/mta-server
        echo -e "${GREEN}[+] Removed mta-server binary${NC}"
    fi
    
    if [ -f "/usr/local/bin/mta-queue" ]; then
        rm -f /usr/local/bin/mta-queue
        echo -e "${GREEN}[+] Removed mta-queue binary${NC}"
    fi
}

# Remove queue directory and emails
remove_queue() {
    echo -e "${YELLOW}[+] Removing queue directory...${NC}"
    
    if [ -d "$QUEUE_DIR" ]; then
        # Count emails before removal
        EMAIL_COUNT=$(find "$QUEUE_DIR" -name "mail-*.eml" 2>/dev/null | wc -l)
        
        if [ $EMAIL_COUNT -gt 0 ]; then
            echo -e "${YELLOW}[!] Found $EMAIL_COUNT emails in queue${NC}"
            read -p "Do you want to backup emails before removal? (yes/no): " backup_emails
            
            if [[ $backup_emails == "yes" ]]; then
                BACKUP_DIR="/tmp/mta_backup_$(date +%Y%m%d_%H%M%S)"
                mkdir -p "$BACKUP_DIR"
                cp -r "$QUEUE_DIR"/* "$BACKUP_DIR/"
                echo -e "${GREEN}[+] Emails backed up to: $BACKUP_DIR${NC}"
            fi
        fi
        
        rm -rf "$QUEUE_DIR"
        echo -e "${GREEN}[+] Removed queue directory: $QUEUE_DIR${NC}"
    fi
}

# Remove log files
remove_logs() {
    echo -e "${YELLOW}[+] Removing log files...${NC}"
    
    if [ -f "$LOG_DIR/mta-server.log" ]; then
        rm -f "$LOG_DIR/mta-server.log"
        echo -e "${GREEN}[+] Removed mta-server.log${NC}"
    fi
    
    if [ -f "$LOG_DIR/mta-server.err" ]; then
        rm -f "$LOG_DIR/mta-server.err"
        echo -e "${GREEN}[+] Removed mta-server.err${NC}"
    fi
    
    if [ -f "$LOG_DIR/mta-queue.log" ]; then
        rm -f "$LOG_DIR/mta-queue.log"
        echo -e "${GREEN}[+] Removed mta-queue.log${NC}"
    fi
    
    if [ -f "$LOG_DIR/mta-queue.err" ]; then
        rm -f "$LOG_DIR/mta-queue.err"
        echo -e "${GREEN}[+] Removed mta-queue.err${NC}"
    fi
}

# Remove users file
remove_users_file() {
    echo -e "${YELLOW}[+] Removing users file...${NC}"
    
    if [ -f "$USERS_FILE" ]; then
        rm -f "$USERS_FILE"
        echo -e "${GREEN}[+] Removed users file: $USERS_FILE${NC}"
    fi
}

# Remove SSL certificates (optional)
remove_ssl_certificates() {
    echo -e "${YELLOW}[+] SSL Certificate Management${NC}"
    echo ""
    echo "SSL certificates are managed by Let's Encrypt and may be used by other services."
    echo "Options:"
    echo "1. Remove only MTA-related certificates"
    echo "2. Keep all certificates (recommended)"
    echo "3. Remove all Let's Encrypt certificates"
    echo ""
    read -p "Choose option (1/2/3): " ssl_option
    
    case $ssl_option in
        1)
            echo -e "${YELLOW}[+] Removing MTA-related SSL certificates...${NC}"
            # Remove renewal hooks
            if [ -f "/etc/letsencrypt/renewal-hooks/post/mta-restart.sh" ]; then
                rm -f /etc/letsencrypt/renewal-hooks/post/mta-restart.sh
                echo -e "${GREEN}[+] Removed MTA renewal hook${NC}"
            fi
            ;;
        2)
            echo -e "${GREEN}[+] Keeping all SSL certificates${NC}"
            ;;
        3)
            echo -e "${RED}[!] Removing all Let's Encrypt certificates...${NC}"
            read -p "Are you sure? This will affect ALL services using Let's Encrypt! (yes/no): " confirm_ssl
            
            if [[ $confirm_ssl == "yes" ]]; then
                if command -v certbot &> /dev/null; then
                    certbot delete --all
                    echo -e "${GREEN}[+] Removed all Let's Encrypt certificates${NC}"
                fi
            else
                echo -e "${YELLOW}[+] Keeping SSL certificates${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}[+] Keeping all SSL certificates${NC}"
            ;;
    esac
}

# Remove firewall rules
remove_firewall_rules() {
    echo -e "${YELLOW}[+] Removing firewall rules...${NC}"
    
    # Remove UFW rules
    if command -v ufw &> /dev/null; then
        ufw delete allow 465/tcp 2>/dev/null || true
        ufw delete allow 587/tcp 2>/dev/null || true
        echo -e "${GREEN}[+] Removed UFW rules for ports 465 and 587${NC}"
    fi
    
    # Remove iptables rules (basic cleanup)
    if command -v iptables &> /dev/null; then
        iptables -D INPUT -p tcp --dport 465 -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -p tcp --dport 587 -j ACCEPT 2>/dev/null || true
        echo -e "${GREEN}[+] Removed iptables rules for ports 465 and 587${NC}"
    fi
}

# Clean up Go installation (optional)
cleanup_go() {
    echo -e "${YELLOW}[+] Go Installation Cleanup${NC}"
    echo ""
    echo "Go may be used by other applications on this system."
    read -p "Do you want to remove Go installation? (yes/no): " remove_go
    
    if [[ $remove_go == "yes" ]]; then
        echo -e "${YELLOW}[+] Removing Go installation...${NC}"
        
        # Remove Go from PATH
        sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' /etc/profile
        
        # Remove Go installation
        if [ -d "/usr/local/go" ]; then
            rm -rf /usr/local/go
            echo -e "${GREEN}[+] Removed Go installation${NC}"
        fi
        
        # Remove Go binaries
        if [ -f "/usr/local/bin/go" ]; then
            rm -f /usr/local/bin/go
            echo -e "${GREEN}[+] Removed Go binary${NC}"
        fi
    else
        echo -e "${GREEN}[+] Keeping Go installation${NC}"
    fi
}

# Final cleanup
final_cleanup() {
    echo -e "${YELLOW}[+] Performing final cleanup...${NC}"
    
    # Remove any remaining temporary files
    find /tmp -name "*mta*" -type f -delete 2>/dev/null || true
    find /tmp -name "*gomail*" -type f -delete 2>/dev/null || true
    
    # Clear any cached data
    systemctl daemon-reload
    
    echo -e "${GREEN}[+] Final cleanup completed${NC}"
}

# Display uninstall summary
display_summary() {
    echo -e "${GREEN}"
    echo "🎉 Uninstallation Complete!"
    echo "=========================="
    echo ""
    echo "✅ Removed components:"
    echo "   - MTA server and queue processor"
    echo "   - Systemd services"
    echo "   - Queue directory and emails"
    echo "   - Log files"
    echo "   - Configuration files"
    echo "   - Firewall rules"
    echo ""
    echo "📋 Next steps:"
    echo "   - Update Acelle Mail configuration"
    echo "   - Remove any DNS records if needed"
    echo "   - Clean up any backups if created"
    echo ""
    echo "⚠️  Note: SSL certificates may still exist if you chose to keep them"
    echo ""
    echo -e "${NC}"
}

# Main uninstall process
main() {
    echo -e "${BLUE}Starting uninstallation...${NC}"
    echo ""
    
    confirm_uninstall
    stop_services
    remove_services
    remove_mta_files
    remove_queue
    remove_logs
    remove_users_file
    remove_ssl_certificates
    remove_firewall_rules
    cleanup_go
    final_cleanup
    display_summary
    
    echo -e "${GREEN}✅ Uninstallation completed successfully!${NC}"
}

# Run main function
main
