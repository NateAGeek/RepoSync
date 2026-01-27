#!/bin/bash
# ============================================
# RepoSync - Add Syncthing Device Script
# ============================================
# Adds a new Syncthing device to the vault and
# optionally re-runs the Syncthing role to apply.
#
# Usage:
#   ./add-device.sh                    # Interactive prompts
#   ./add-device.sh --name "macbook" --id "XXXX-XXXX-..."
#   ./add-device.sh --apply            # Apply changes after adding
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
DEVICE_NAME=""
DEVICE_ID=""
APPLY_CHANGES=false
LIST_DEVICES=false

show_help() {
    echo -e "${BLUE}RepoSync - Add Syncthing Device${NC}"
    echo ""
    echo "Usage: ./add-device.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -n, --name NAME     Device name (e.g., windows-pc, macbook)"
    echo "  -i, --id ID         Device ID (from 'syncthing --device-id')"
    echo "  -a, --apply         Apply changes by running Syncthing role"
    echo "  -l, --list          List currently configured devices"
    echo "  --local             Apply to localhost"
    echo ""
    echo "Examples:"
    echo "  ./add-device.sh                           # Interactive mode"
    echo "  ./add-device.sh -n macbook -i XXXX-XXXX   # Direct mode"
    echo "  ./add-device.sh --list                    # Show devices"
    echo "  ./add-device.sh -n pc -i XXXX --apply     # Add and apply"
    echo ""
}

# Check vault exists
check_vault() {
    if [[ ! -f "$VAULT_FILE" ]] || [[ ! -f "$VAULT_PASS_FILE" ]]; then
        echo -e "${RED}Error: Vault not found. Run ./setup.sh first.${NC}"
        exit 1
    fi
}

# Decrypt vault to temp file
decrypt_vault() {
    TEMP_VAULT=$(mktemp)
    ansible-vault decrypt --vault-password-file "$VAULT_PASS_FILE" --output "$TEMP_VAULT" "$VAULT_FILE"
    echo "$TEMP_VAULT"
}

# List current devices
list_devices() {
    check_vault
    
    echo -e "${BLUE}Current Syncthing Devices:${NC}"
    echo ""
    
    local temp_file=$(decrypt_vault)
    
    # Extract devices using grep/sed
    local devices=$(grep -A 100 "vault_syncthing_devices:" "$temp_file" | head -1 | sed 's/vault_syncthing_devices: //')
    
    if [[ "$devices" == "[]" ]] || [[ -z "$devices" ]]; then
        echo "  (no devices configured)"
    else
        # Parse JSON array
        echo "$devices" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for i, d in enumerate(devices, 1):
        print(f\"  {i}. {d.get('name', 'unknown')}: {d.get('id', 'no-id')}\")
except:
    print('  (unable to parse devices)')
" 2>/dev/null || echo "  $devices"
    fi
    
    rm -f "$temp_file"
    echo ""
}

# Add device to vault
add_device() {
    local name="$1"
    local id="$2"
    
    check_vault
    
    echo -e "${YELLOW}Adding device: $name${NC}"
    
    # Decrypt vault
    local temp_file=$(decrypt_vault)
    
    # Extract current devices
    local current_devices=$(grep "vault_syncthing_devices:" "$temp_file" | sed 's/vault_syncthing_devices: //')
    
    # Build new device entry
    local new_device="{\"name\": \"$name\", \"id\": \"$id\"}"
    
    # Add to array
    local new_devices
    if [[ "$current_devices" == "[]" ]] || [[ -z "$current_devices" ]]; then
        new_devices="[$new_device]"
    else
        # Remove trailing ] and add new device
        new_devices=$(echo "$current_devices" | python3 -c "
import sys, json
devices = json.load(sys.stdin)
devices.append({'name': '$name', 'id': '$id'})
print(json.dumps(devices))
" 2>/dev/null)
        
        if [[ -z "$new_devices" ]]; then
            # Fallback: simple string manipulation
            new_devices="${current_devices%]}, $new_device]"
        fi
    fi
    
    # Update the temp file
    sed -i "s|vault_syncthing_devices:.*|vault_syncthing_devices: $new_devices|" "$temp_file"
    
    # Re-encrypt
    ansible-vault encrypt --vault-password-file "$VAULT_PASS_FILE" --output "$VAULT_FILE" "$temp_file"
    
    rm -f "$temp_file"
    
    echo -e "${GREEN}Device added successfully!${NC}"
    echo ""
}

# Apply changes
apply_changes() {
    local limit="${1:-all}"
    
    echo -e "${YELLOW}Applying Syncthing configuration...${NC}"
    echo ""
    
    local cmd="ansible-playbook playbooks/site.yml --limit $limit --tags syncthing --vault-password-file $VAULT_PASS_FILE"
    
    if [[ "$limit" == "localhost" ]] && [[ $EUID -ne 0 ]]; then
        cmd="$cmd --ask-become-pass"
    fi
    
    echo -e "${GREEN}Running:${NC} $cmd"
    echo ""
    
    eval $cmd
}

# Parse arguments
LIMIT="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--name)
            DEVICE_NAME="$2"
            shift 2
            ;;
        -i|--id)
            DEVICE_ID="$2"
            shift 2
            ;;
        -a|--apply)
            APPLY_CHANGES=true
            shift
            ;;
        -l|--list)
            LIST_DEVICES=true
            shift
            ;;
        --local)
            LIMIT="localhost"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  RepoSync - Add Syncthing Device${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# List mode
if [[ "$LIST_DEVICES" == "true" ]]; then
    list_devices
    exit 0
fi

# Interactive mode if no name/id provided
if [[ -z "$DEVICE_NAME" ]]; then
    echo -e "${GREEN}Enter device details:${NC}"
    read -p "  Device name (e.g., windows-pc, macbook): " DEVICE_NAME
    
    if [[ -z "$DEVICE_NAME" ]]; then
        echo -e "${RED}Error: Device name is required${NC}"
        exit 1
    fi
fi

if [[ -z "$DEVICE_ID" ]]; then
    echo "  Get the device ID by running 'syncthing --device-id' on the device"
    read -p "  Device ID: " DEVICE_ID
    
    if [[ -z "$DEVICE_ID" ]]; then
        echo -e "${RED}Error: Device ID is required${NC}"
        exit 1
    fi
fi

# Validate device ID format (should be like XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX)
if [[ ! "$DEVICE_ID" =~ ^[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}-[A-Z0-9]{7}$ ]]; then
    echo -e "${YELLOW}Warning: Device ID format looks unusual. Expected format: XXXXXXX-XXXXXXX-...${NC}"
    read -p "Continue anyway? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        exit 1
    fi
fi

# Add the device
add_device "$DEVICE_NAME" "$DEVICE_ID"

# Show current devices
list_devices

# Ask to apply if not specified
if [[ "$APPLY_CHANGES" != "true" ]]; then
    read -p "Apply changes now? (y/N): " apply_now
    if [[ "$apply_now" == "y" || "$apply_now" == "Y" ]]; then
        APPLY_CHANGES=true
    fi
fi

# Apply if requested
if [[ "$APPLY_CHANGES" == "true" ]]; then
    apply_changes "$LIMIT"
fi

echo -e "${GREEN}Done!${NC}"
echo ""
echo "Next steps on the new device:"
echo "  1. Open Syncthing GUI"
echo "  2. Add this VPS as a remote device using its Device ID"
echo "  3. Accept the folder share when prompted"
