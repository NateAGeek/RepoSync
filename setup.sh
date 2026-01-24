#!/bin/bash
# ============================================
# RepoSync - Quick Setup Script
# ============================================
# Simple wrapper to run the Ansible playbook
# with interactive prompts for easy VPS setup.
#
# Usage:
#   ./setup.sh              # Full run with prompts
#   ./setup.sh --check      # Dry run (no changes)
#   ./setup.sh --tags ssh   # Run specific roles
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

# Default values
CHECK_MODE=""
LIMIT="all"
TAGS=""
SKIP_TAGS=""
VERBOSE=""
EXTRA_ARGS=""

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
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                     # Full interactive setup"
    echo "  ./setup.sh --check             # Dry run, see what would change"
    echo "  ./setup.sh --local             # Run on localhost"
    echo "  ./setup.sh --tags github       # Only run GitHub roles"
    echo "  ./setup.sh --skip firewall     # Skip firewall configuration"
    echo "  ./setup.sh -t ssh,firewall     # Only run SSH and firewall"
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

# Show what we're about to do
echo -e "${GREEN}Configuration:${NC}"
echo "  Target: $LIMIT"
[[ -n "$CHECK_MODE" ]] && echo -e "  Mode: ${YELLOW}DRY RUN (no changes)${NC}" || echo "  Mode: Full run"
[[ -n "$TAGS" ]] && echo "  Tags: ${TAGS#--tags }"
[[ -n "$SKIP_TAGS" ]] && echo "  Skip: ${SKIP_TAGS#--skip-tags }"
echo ""

# Build the command
CMD="ansible-playbook playbooks/site.yml --limit $LIMIT $CHECK_MODE $TAGS $SKIP_TAGS $VERBOSE $EXTRA_ARGS"

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
