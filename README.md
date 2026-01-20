# Ansible Infrastructure

This Ansible project configures servers with:
- **Tailscale VPN** - Secure mesh networking
- **UFW Firewall** - Restricts access to Tailscale network only
- **Syncthing** - Continuous file synchronization
- **GitHub Repos** - Clone private repositories

## Quick Start

### 1. Set up secrets

```bash
# Copy the vault example
cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml

# Edit with your secrets
nano inventory/group_vars/all/vault.yml

# Encrypt the vault
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

### 2. Configure inventory

Edit `inventory/hosts.yml` to add your servers:

```yaml
all:
  children:
    servers:
      hosts:
        myserver:
          ansible_host: 192.168.1.10
          ansible_user: ubuntu
          tailscale_ip: 100.64.0.1
```

### 3. Configure variables

Edit `inventory/group_vars/all/main.yml` to configure:
- Syncthing folders and devices
- GitHub repositories to clone
- Additional firewall ports

### 4. Run the playbook

```bash
# Full run
ansible-playbook playbooks/site.yml --ask-vault-pass

# Or with vault password file
ansible-playbook playbooks/site.yml --vault-password-file ~/.vault_pass

# Run specific roles
ansible-playbook playbooks/site.yml --tags "firewall" --ask-vault-pass
```

## Project Structure

```
.
├── ansible.cfg                    # Ansible configuration
├── inventory/
│   ├── hosts.yml                  # Server inventory
│   └── group_vars/
│       └── all/
│           ├── main.yml           # Variables
│           └── vault.yml          # Secrets (encrypted)
├── playbooks/
│   └── site.yml                   # Main playbook
└── roles/
    ├── common/                    # Base packages
    ├── tailscale/                 # Tailscale VPN
    ├── firewall/                  # UFW configuration
    ├── syncthing/                 # Syncthing setup
    └── github_repos/              # Clone repositories
```

## Firewall Rules

After deployment, the following firewall rules are active:

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 22 | TCP | 100.64.0.0/10 | SSH (Tailscale only) |
| 8384 | TCP | 100.64.0.0/10 | Syncthing GUI |
| 22000 | TCP | 100.64.0.0/10 | Syncthing sync |
| 21027 | UDP | 100.64.0.0/10 | Syncthing discovery |

All other incoming traffic is blocked. Outgoing traffic is allowed.

## Getting Syncthing Device IDs

After running the playbook, device IDs are displayed in the summary. You can also get them with:

```bash
ansible all -m shell -a "syncthing --home=/home/syncthing/.config/syncthing --device-id"
```

## Requirements

- Ansible 2.12+
- Target: Ubuntu/Debian
- Python 3 on target hosts
- `community.general` collection

Install collections:
```bash
ansible-galaxy collection install community.general
```
