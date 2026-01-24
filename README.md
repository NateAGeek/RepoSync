# RepoSync - VPS Setup Automation

Ansible playbook for quickly setting up a secure VPS with:
- **SSH Hardening** - Non-standard port, ed25519 only, no root login
- **SSHGuard** - Brute-force protection
- **UFW Firewall** - Strict inbound/outbound rules
- **GitHub Repos** - Auto-discover and clone all your repositories
- **Syncthing** - Continuous file synchronization

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/yourusername/RepoSync.git
cd RepoSync

# 2. Run the test script to check prerequisites
./test.sh

# 3. Run setup (interactive - prompts for all secrets)
./setup.sh --local        # Test on localhost first
./setup.sh                # Run on all configured hosts
```

That's it! The playbook will prompt you for:
- SSH public key
- GitHub username
- GitHub Personal Access Token
- Path to SSH key for GitHub
- Syncthing GUI password

## Utility Scripts

| Script | Purpose |
|--------|---------|
| `./setup.sh` | Run the playbook (main entry point) |
| `./test.sh` | Validate configuration and prerequisites |
| `./reset.sh` | Undo/reset configurations |

### setup.sh Examples

```bash
./setup.sh                    # Full interactive setup
./setup.sh --check            # Dry run (no changes made)
./setup.sh --local            # Run on localhost only
./setup.sh --tags github      # Only run GitHub-related roles
./setup.sh --skip firewall    # Skip firewall configuration
./setup.sh -v                 # Verbose output
```

### reset.sh Examples

```bash
./reset.sh --firewall         # Disable UFW
./reset.sh --ssh              # Reset SSH to defaults
./reset.sh --syncthing        # Stop Syncthing service
./reset.sh --repos            # Remove cloned repos
./reset.sh --all              # Reset everything
```

## Configuration

### Add Your VPS

Edit `inventory/hosts.yml`:

```yaml
all:
  children:
    servers:
      hosts:
        my-vps:
          ansible_host: 123.45.67.89
          ansible_user: root
```

### Set GitHub Username

Edit `inventory/group_vars/all/main.yml`:

```yaml
github_username: "YourGitHubUsername"
```

### Optional: Pre-configure Secrets

Instead of entering secrets interactively, you can use Ansible Vault:

```bash
# Create vault from example
cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml

# Edit with your secrets
nano inventory/group_vars/all/vault.yml

# Encrypt it
ansible-vault encrypt inventory/group_vars/all/vault.yml

# Run with vault
./setup.sh  # Just press Enter at prompts to use vault values
```

## What Gets Configured

### SSH Security
- Custom port (default: 9438)
- Ed25519 keys only
- Root login disabled
- Password auth disabled
- Dedicated `deploy` user created

### Firewall (UFW)
- **Inbound**: Deny all except SSH port
- **Outbound**: Deny all except DNS, NTP, HTTP, HTTPS
- Rate limiting on SSH

### GitHub Integration
- Auto-discovers all your repos via GitHub API
- Clones to `/opt/repos/{owner}/{repo}`
- Excludes forks and archived repos
- Cron job syncs every 15 minutes

### Syncthing
- Syncs `/opt/repos` folder
- GUI accessible via SSH tunnel
- `.stignore` configured to sync git config but not object database

## Connecting After Setup

```bash
# SSH access (note the custom port)
ssh -p 9438 deploy@your-vps-ip

# Syncthing GUI via SSH tunnel
ssh -L 8384:localhost:8384 -p 9438 deploy@your-vps-ip
# Then open: http://localhost:8384
```

## Project Structure

```
.
├── setup.sh                    # Main setup script
├── test.sh                     # Validation script
├── reset.sh                    # Reset/cleanup script
├── ansible.cfg                 # Ansible configuration
├── requirements.yml            # Ansible collections
├── inventory/
│   ├── hosts.yml               # Server inventory
│   └── group_vars/all/
│       ├── main.yml            # Configuration variables
│       └── vault.yml.example   # Secrets template
├── playbooks/
│   └── site.yml                # Main playbook
└── roles/
    ├── common/                 # Base packages
    ├── ssh/                    # SSH hardening
    ├── sshguard/               # Brute-force protection
    ├── firewall/               # UFW configuration
    ├── github_fetch_repos/     # Discover repos via API
    ├── github_repos/           # Clone repositories
    ├── github_sync/            # Cron sync job
    └── syncthing/              # File synchronization
```

## Requirements

- **Local machine**: Ansible 2.12+, Python 3
- **Target VPS**: Ubuntu/Debian, Python 3

```bash
# Install Ansible
pip install ansible

# Install required collections (done automatically by setup.sh)
ansible-galaxy collection install -r requirements.yml
```

## Available Tags

Run specific parts of the playbook:

| Tag | Roles |
|-----|-------|
| `common` | Base packages, updates |
| `ssh` | SSH hardening |
| `sshguard` | Brute-force protection |
| `firewall` | UFW rules |
| `github` | Fetch + clone repos |
| `fetch` | Only discover repos |
| `repos` | Only clone repos |
| `sync` | GitHub cron job |
| `syncthing` | Syncthing setup |

Example: `./setup.sh --tags "ssh,firewall"`

## Troubleshooting

### Locked out of SSH?

Use your VPS provider's console to run:
```bash
./reset.sh --firewall --ssh
```

### GitHub API failing?

Test your token:
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.github.com/user/repos?per_page=1
```

### Syncthing not syncing?

Check the device ID was added on both sides:
```bash
ssh -p 9438 deploy@your-vps "syncthing --device-id"
```
