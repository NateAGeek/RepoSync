#!/bin/bash
# ============================================
# RepoSync - Reset/Clean Script
# ============================================
# Removes configurations applied by the playbook.
# Useful for testing or starting fresh.
#
# Usage:
#   ./reset.sh              # Interactive - asks what to reset
#   ./reset.sh --all        # Reset everything
#   ./reset.sh --firewall   # Reset just firewall
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}This script needs sudo privileges.${NC}"
   exec sudo "$0" "$@"
fi

show_help() {
    echo -e "${BLUE}RepoSync - Reset Script${NC}"
    echo ""
    echo "Usage: ./reset.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Show this help"
    echo "  --all            Reset everything"
    echo "  --firewall       Disable UFW firewall"
    echo "  --ssh            Reset SSH to defaults"
    echo "  --sshguard       Stop and disable SSHGuard"
    echo "  --syncthing      Stop and disable Syncthing"
    echo "  --repos          Remove cloned repositories"
    echo "  --cron           Remove GitHub sync cron job"
    echo ""
}

reset_firewall() {
    echo -e "${YELLOW}Resetting firewall...${NC}"
    if command -v ufw &> /dev/null; then
        ufw --force disable
        ufw --force reset
        echo -e "${GREEN}  UFW disabled and reset${NC}"
    else
        echo "  UFW not installed, skipping"
    fi
}

reset_ssh() {
    echo -e "${YELLOW}Resetting SSH configuration...${NC}"
    
    # Restore default sshd_config if backup exists
    if [[ -f /etc/ssh/sshd_config.bak ]]; then
        cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
        echo -e "${GREEN}  Restored sshd_config from backup${NC}"
    else
        echo "  No backup found, reinstalling openssh-server..."
        apt-get install --reinstall -y openssh-server > /dev/null 2>&1
    fi
    
    # Restart SSH on default port
    systemctl restart sshd || systemctl restart ssh
    echo -e "${GREEN}  SSH service restarted${NC}"
    echo -e "${YELLOW}  Warning: SSH is now on default port 22${NC}"
}

reset_sshguard() {
    echo -e "${YELLOW}Stopping SSHGuard...${NC}"
    if systemctl is-active --quiet sshguard 2>/dev/null; then
        systemctl stop sshguard
        systemctl disable sshguard
        echo -e "${GREEN}  SSHGuard stopped and disabled${NC}"
    else
        echo "  SSHGuard not running"
    fi
}

reset_syncthing() {
    echo -e "${YELLOW}Stopping Syncthing...${NC}"
    
    # Find and stop syncthing services
    for service in $(systemctl list-units --type=service --all | grep syncthing | awk '{print $1}'); do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        echo -e "${GREEN}  Stopped $service${NC}"
    done
    
    # Also check for user service
    if systemctl is-active --quiet syncthing@syncthing 2>/dev/null; then
        systemctl stop syncthing@syncthing
        systemctl disable syncthing@syncthing
        echo -e "${GREEN}  Stopped syncthing@syncthing${NC}"
    fi
}

reset_repos() {
    echo -e "${YELLOW}Removing cloned repositories...${NC}"
    
    REPO_PATH="/opt/repos"
    if [[ -d "$REPO_PATH" ]]; then
        read -p "  Remove $REPO_PATH? This cannot be undone! [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$REPO_PATH"
            echo -e "${GREEN}  Removed $REPO_PATH${NC}"
        else
            echo "  Skipped"
        fi
    else
        echo "  $REPO_PATH does not exist"
    fi
}

reset_cron() {
    echo -e "${YELLOW}Removing GitHub sync cron job...${NC}"
    
    # Remove cron job
    crontab -l 2>/dev/null | grep -v "github-sync" | crontab - 2>/dev/null || true
    
    # Remove script
    if [[ -f /opt/scripts/github-sync.sh ]]; then
        rm -f /opt/scripts/github-sync.sh
        echo -e "${GREEN}  Removed sync script${NC}"
    fi
    
    echo -e "${GREEN}  Cron job removed${NC}"
}

reset_all() {
    echo -e "${RED}This will reset ALL configurations!${NC}"
    read -p "Are you sure? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    reset_cron
    reset_syncthing
    reset_sshguard
    reset_firewall
    reset_ssh
    reset_repos
    
    echo ""
    echo -e "${GREEN}All configurations reset.${NC}"
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --all)
            reset_all
            exit 0
            ;;
        --firewall)
            reset_firewall
            shift
            ;;
        --ssh)
            reset_ssh
            shift
            ;;
        --sshguard)
            reset_sshguard
            shift
            ;;
        --syncthing)
            reset_syncthing
            shift
            ;;
        --repos)
            reset_repos
            shift
            ;;
        --cron)
            reset_cron
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo ""
echo -e "${GREEN}Done!${NC}"
