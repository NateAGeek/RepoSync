#!/bin/bash
# ============================================
# RepoSync - Quick Setup Script
# ============================================
# Simple wrapper to run the Ansible playbook
# with interactive prompts for easy VPS setup.
# Caches credentials in an encrypted vault file.
#
# Usage:
#   ./setup.sh              # Full run with prompts
#   ./setup.sh --check      # Dry run (no changes)
#   ./setup.sh --tags ssh   # Run specific roles
#   ./setup.sh --reconfigure # Re-enter all credentials
#   ./setup.sh --help       # Show help
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Vault configuration
VAULT_FILE="$SCRIPT_DIR/inventory/group_vars/all/vault.yml"
VAULT_PASS_FILE="$SCRIPT_DIR/.vault_pass"

# Default values
CHECK_MODE=""
LIMIT="all"
TAGS=""
SKIP_TAGS=""
VERBOSE=""
EXTRA_ARGS=""
RECONFIGURE=false
USE_PROMPTS=false

show_help() {
    echo -e "${BLUE}RepoSync - VPS Setup Script${NC}"
    echo ""
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --check         Dry run - show what would change (no modifications)"
    echo "  -l, --limit HOST    Limit to specific host (default: all)"
    echo "  -t, --tags TAGS     Only run specific roles (comma-separated)"
    echo "  -s, --skip TAGS     Skip specific roles (comma-separated)"
    echo "  -v, --verbose       Verbose output"
    echo "  --local             Run on localhost only"
    echo "  --reconfigure       Re-enter all credentials (update vault)"
    echo "  --prompts           Use interactive prompts instead of vault"
    echo ""
    echo "Credentials:"
    echo "  On first run, you'll be prompted for credentials which are saved"
    echo "  to an encrypted vault file. Subsequent runs use the cached values."
    echo ""
    echo "  Vault file: $VAULT_FILE"
    echo "  Password file: $VAULT_PASS_FILE (auto-generated, keep secret!)"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                     # Full setup (uses cached creds)"
    echo "  ./setup.sh --check             # Dry run, see what would change"
    echo "  ./setup.sh --local             # Run on localhost"
    echo "  ./setup.sh --reconfigure       # Update saved credentials"
    echo "  ./setup.sh --tags github       # Only run GitHub roles"
    echo "  ./setup.sh --skip firewall     # Skip firewall configuration"
    echo ""
    echo "Available tags:"
    echo "  common      - Base packages and updates"
    echo "  sshguard    - SSH brute-force protection"
    echo "  ssh         - SSH hardening"
    echo "  firewall    - UFW firewall rules"
    echo "  github      - GitHub repo fetch + clone"
    echo "  fetch       - Only fetch repo list from GitHub API"
    echo "  repos       - Only clone repositories"
    echo "  sync        - GitHub sync cron job"
    echo "  syncthing   - Syncthing file sync"
    echo ""
}

# Generate a random vault password
generate_vault_password() {
    if [[ ! -f "$VAULT_PASS_FILE" ]]; then
        echo -e "${YELLOW}Generating vault password...${NC}"
        openssl rand -base64 32 > "$VAULT_PASS_FILE"
        chmod 600 "$VAULT_PASS_FILE"
        echo -e "${GREEN}Vault password saved to: $VAULT_PASS_FILE${NC}"
        echo -e "${YELLOW}Keep this file secure! It's needed to decrypt your credentials.${NC}"
        echo ""
    fi
}

# Prompt for a value with optional default
prompt_value() {
    local prompt_text="$1"
    local default_value="$2"
    local is_secret="$3"
    local result=""
    
    if [[ "$is_secret" == "true" ]]; then
        read -s -p "$prompt_text" result
        echo ""
    else
        read -p "$prompt_text" result
    fi
    
    if [[ -z "$result" ]]; then
        result="$default_value"
    fi
    
    echo "$result"
}

# Collect Syncthing devices interactively
collect_syncthing_devices() {
    SYNCTHING_DEVICES=()
    
    echo -e "${GREEN}SYNCTHING DEVICES${NC}"
    echo "Add devices to sync with (Windows, Mac, etc.)"
    echo "Get device ID by running 'syncthing --device-id' on each machine"
    echo ""
    
    local add_more="y"
    local device_num=1
    
    while [[ "$add_more" == "y" || "$add_more" == "Y" ]]; do
        echo -e "${BLUE}Device $device_num:${NC}"
        read -p "  Device name (e.g., windows-pc, macbook): " device_name
        
        if [[ -z "$device_name" ]]; then
            break
        fi
        
        read -p "  Device ID: " device_id
        
        if [[ -z "$device_id" ]]; then
            echo -e "${YELLOW}  Skipping - no device ID provided${NC}"
        else
            SYNCTHING_DEVICES+=("{\"name\": \"$device_name\", \"id\": \"$device_id\"}")
            echo -e "${GREEN}  Added: $device_name${NC}"
            ((device_num++))
        fi
        
        echo ""
        read -p "Add another device? (y/N): " add_more
        echo ""
    done
    
    # Build YAML array
    CRED_SYNCTHING_DEVICES=""
    if [[ ${#SYNCTHING_DEVICES[@]} -gt 0 ]]; then
        CRED_SYNCTHING_DEVICES="["
        for i in "${!SYNCTHING_DEVICES[@]}"; do
            if [[ $i -gt 0 ]]; then
                CRED_SYNCTHING_DEVICES+=", "
            fi
            CRED_SYNCTHING_DEVICES+="${SYNCTHING_DEVICES[$i]}"
        done
        CRED_SYNCTHING_DEVICES+="]"
    else
        CRED_SYNCTHING_DEVICES="[]"
    fi
}

# Collect credentials interactively
collect_credentials() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  Credential Setup${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    
    # SSH Public Key
    echo -e "${GREEN}SSH ACCESS SETUP${NC}"
    echo "Enter your SSH public key (ed25519)"
    echo "Example: ssh-ed25519 AAAA... user@host"
    read -p "> " CRED_SSH_PUBLIC_KEY
    echo ""
    
    # GitHub Username
    echo -e "${GREEN}GITHUB SETUP${NC}"
    read -p "Enter your GitHub username: " CRED_GITHUB_USERNAME
    
    # GitHub Token
    echo "Enter your GitHub Personal Access Token"
    echo "(Get one at https://github.com/settings/tokens - needs 'repo' scope)"
    read -s -p "> " CRED_GITHUB_TOKEN
    echo ""
    
    # GitHub SSH Key Path
    echo "Enter the path to your SSH private key ON THE TARGET SYSTEM"
    echo "Example: /root/.ssh/id_ed25519"
    read -p "> " CRED_GITHUB_SSH_KEY_PATH
    echo ""
    
    # Syncthing Password
    echo -e "${GREEN}SYNCTHING SETUP${NC}"
    echo "Enter a password for Syncthing Web GUI (leave blank for no auth)"
    read -s -p "> " CRED_SYNCTHING_PASSWORD
    echo ""
    echo ""
    
    # Syncthing Devices
    collect_syncthing_devices
}

# Save credentials to encrypted vault
save_vault() {
    echo -e "${YELLOW}Saving credentials to vault...${NC}"
    
    # Create the vault content
    local vault_content="---
# Ansible Vault - Encrypted Credentials
# Generated by setup.sh - Do not edit manually
# To update, run: ./setup.sh --reconfigure
# To add a device, run: ./add-device.sh

# SSH public key for the deploy user
vault_ssh_user_public_key: \"$CRED_SSH_PUBLIC_KEY\"

# GitHub credentials
vault_github_username: \"$CRED_GITHUB_USERNAME\"
vault_github_token: \"$CRED_GITHUB_TOKEN\"
vault_github_ssh_key_path: \"$CRED_GITHUB_SSH_KEY_PATH\"

# Syncthing GUI password
vault_syncthing_gui_password: \"$CRED_SYNCTHING_PASSWORD\"

# Syncthing remote devices
vault_syncthing_devices: $CRED_SYNCTHING_DEVICES
"
    
    # Ensure directory exists
    mkdir -p "$(dirname "$VAULT_FILE")"
    
    # Encrypt and save
    echo "$vault_content" | ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" --output "$VAULT_FILE"
    
    echo -e "${GREEN}Credentials saved to: $VAULT_FILE${NC}"
    echo ""
}

# Check if vault exists and is valid
vault_exists() {
    [[ -f "$VAULT_FILE" ]] && [[ -f "$VAULT_PASS_FILE" ]]
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--check)
            CHECK_MODE="--check --diff"
            shift
            ;;
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -t|--tags)
            TAGS="--tags $2"
            shift 2
            ;;
        -s|--skip)
            SKIP_TAGS="--skip-tags $2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        --local)
            LIMIT="localhost"
            shift
            ;;
        --reconfigure)
            RECONFIGURE=true
            shift
            ;;
        --prompts)
            USE_PROMPTS=true
            shift
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  RepoSync - VPS Setup${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: Ansible is not installed.${NC}"
    echo ""
    echo "Install with:"
    echo "  pip install ansible"
    echo "  # or"
    echo "  sudo apt install ansible"
    exit 1
fi

# Check if collections are installed
if ! ansible-galaxy collection list 2>/dev/null | grep -q "community.general"; then
    echo -e "${YELLOW}Installing required Ansible collections...${NC}"
    ansible-galaxy collection install -r requirements.yml
    echo ""
fi

# Handle vault/credentials
VAULT_ARGS=""

if [[ "$USE_PROMPTS" == "true" ]]; then
    echo -e "${YELLOW}Using interactive prompts (--prompts flag)${NC}"
    echo ""
elif [[ "$RECONFIGURE" == "true" ]] || ! vault_exists; then
    if [[ "$RECONFIGURE" == "true" ]]; then
        echo -e "${YELLOW}Reconfiguring credentials...${NC}"
    else
        echo -e "${YELLOW}First time setup - collecting credentials...${NC}"
    fi
    echo ""
    
    # Generate vault password if needed
    generate_vault_password
    
    # Collect credentials
    collect_credentials
    
    # Save to vault
    save_vault
    
    # Use vault for this run
    VAULT_ARGS="--vault-password-file $VAULT_PASS_FILE"
else
    echo -e "${GREEN}Using cached credentials from vault${NC}"
    echo "  (run with --reconfigure to update)"
    echo ""
    VAULT_ARGS="--vault-password-file $VAULT_PASS_FILE"
fi

# Show what we're about to do
echo -e "${GREEN}Configuration:${NC}"
echo "  Target: $LIMIT"
[[ -n "$CHECK_MODE" ]] && echo -e "  Mode: ${YELLOW}DRY RUN (no changes)${NC}" || echo "  Mode: Full run"
[[ -n "$TAGS" ]] && echo "  Tags: ${TAGS#--tags }"
[[ -n "$SKIP_TAGS" ]] && echo "  Skip: ${SKIP_TAGS#--skip-tags }"
[[ -n "$VAULT_ARGS" ]] && echo "  Vault: Using encrypted credentials"
echo ""

# Build the command
CMD="ansible-playbook playbooks/site.yml --limit $LIMIT $CHECK_MODE $TAGS $SKIP_TAGS $VERBOSE $VAULT_ARGS $EXTRA_ARGS"

# Add become password prompt for non-root
if [[ "$LIMIT" == "localhost" ]] && [[ $EUID -ne 0 ]]; then
    CMD="$CMD --ask-become-pass"
fi

echo -e "${GREEN}Running:${NC} $CMD"
echo ""

# Run it
eval $CMD

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Done!${NC}"
echo -e "${GREEN}============================================${NC}"

# Remind about vault password file
if [[ -f "$VAULT_PASS_FILE" ]]; then
    echo ""
    echo -e "${YELLOW}Remember: Keep $VAULT_PASS_FILE secure!${NC}"
    echo "It's required to decrypt your saved credentials."
fi
