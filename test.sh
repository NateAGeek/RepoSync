#!/bin/bash
# ============================================
# RepoSync - Test Script
# ============================================
# Runs validation checks without making changes.
#
# Usage:
#   ./test.sh           # Run all checks
#   ./test.sh --syntax  # Syntax check only
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  RepoSync - Test & Validation${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

ERRORS=0

# Check Ansible installed
echo -n "Checking Ansible installation... "
if command -v ansible-playbook &> /dev/null; then
    VERSION=$(ansible --version | head -n1)
    echo -e "${GREEN}OK${NC} ($VERSION)"
else
    echo -e "${RED}MISSING${NC}"
    echo "  Install with: pip install ansible"
    ERRORS=$((ERRORS + 1))
fi

# Check collections
echo -n "Checking Ansible collections... "
if ansible-galaxy collection list 2>/dev/null | grep -q "community.general"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}MISSING${NC}"
    echo "  Run: ansible-galaxy collection install -r requirements.yml"
    ERRORS=$((ERRORS + 1))
fi

# Syntax check
echo -n "Checking playbook syntax... "
if ansible-playbook playbooks/site.yml --syntax-check > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    ansible-playbook playbooks/site.yml --syntax-check
    ERRORS=$((ERRORS + 1))
fi

# Check inventory
echo -n "Checking inventory... "
HOST_COUNT=$(ansible-inventory --list 2>/dev/null | grep -c '"ansible_host"' || echo "0")
if [[ "$HOST_COUNT" -gt 0 ]] || ansible-inventory --list 2>/dev/null | grep -q "localhost"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}No hosts configured${NC}"
    echo "  Edit inventory/hosts.yml to add your servers"
fi

# List tasks
echo ""
echo -e "${BLUE}Available roles and tags:${NC}"
ansible-playbook playbooks/site.yml --list-tags 2>/dev/null | grep "TASK TAGS" | sed 's/.*\[/  /' | sed 's/\]//'

# Check for vault
echo ""
echo -n "Checking vault file... "
if [[ -f "inventory/group_vars/all/vault.yml" ]]; then
    if head -n1 "inventory/group_vars/all/vault.yml" | grep -q "^\$ANSIBLE_VAULT"; then
        echo -e "${GREEN}OK (encrypted)${NC}"
    else
        echo -e "${YELLOW}WARNING: vault.yml exists but is NOT encrypted!${NC}"
        echo "  Run: ansible-vault encrypt inventory/group_vars/all/vault.yml"
    fi
else
    echo -e "${YELLOW}Not created${NC}"
    echo "  Optional: Copy vault.yml.example to vault.yml for storing secrets"
fi

# Check main.yml configuration
echo ""
echo -e "${BLUE}Current configuration:${NC}"
echo -n "  github_username: "
USERNAME=$(grep "^github_username:" inventory/group_vars/all/main.yml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [[ -n "$USERNAME" && "$USERNAME" != '""' ]]; then
    echo -e "${GREEN}$USERNAME${NC}"
else
    echo -e "${YELLOW}not set${NC}"
fi

echo -n "  github_ssh_key_path: "
KEY_PATH=$(grep "^github_ssh_key_path:" inventory/group_vars/all/main.yml 2>/dev/null | awk '{print $2}' | tr -d '"')
if [[ -n "$KEY_PATH" && "$KEY_PATH" != '""' ]]; then
    echo -e "${GREEN}$KEY_PATH${NC}"
else
    echo -e "${YELLOW}not set (will prompt)${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}============================================${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  ./setup.sh --check    # Dry run"
    echo "  ./setup.sh --local    # Run on localhost"
    echo "  ./setup.sh            # Full setup"
else
    echo -e "${RED}$ERRORS error(s) found.${NC}"
    echo "Fix the issues above before running setup."
    exit 1
fi
echo -e "${BLUE}============================================${NC}"
