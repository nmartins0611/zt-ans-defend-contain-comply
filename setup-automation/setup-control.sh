#!/bin/bash
set -euo pipefail

echo "Starting Control node setup (bootstrap phase)..."
export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False

###############################################################################
# Helpers
###############################################################################

retry() {
    local max_attempts=3
    local delay=5
    local desc="$1"
    shift
    for ((i = 1; i <= max_attempts; i++)); do
        echo "Attempt $i/$max_attempts: $desc"
        if "$@"; then
            return 0
        fi
        if [ $i -lt $max_attempts ]; then
            echo "  Failed. Retrying in ${delay}s..."
            sleep $delay
        fi
    done
    echo "FATAL: Failed after $max_attempts attempts: $desc"
    exit 1
}

run_if_needed() {
    local desc="$1"
    shift
    local check=()
    while [[ $# -gt 0 && "${1}" != "--" ]]; do
        check+=("$1"); shift
    done
    shift
    if "${check[@]}" &>/dev/null; then
        echo "SKIP (already done): $desc"
    else
        retry "$desc" "$@"
    fi
}

###############################################################################
# 1. Validate required environment variables
###############################################################################

for var in TMM_ORG TMM_ID AH_TOKEN; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var environment variable is not set"
        exit 1
    fi
done

###############################################################################
# 2. Enable subscription-manager repo management (idempotent)
###############################################################################

CURRENT_MANAGE_REPOS=$(subscription-manager config --list | grep -oP 'manage_repos\s*=\s*\[\K[^\]]+' || echo "unknown")
if [ "$CURRENT_MANAGE_REPOS" = "1" ]; then
    echo "SKIP: manage_repos already enabled"
else
    subscription-manager config --rhsm.manage_repos=1
    subscription-manager refresh
fi

###############################################################################
# 3. Setup Ansible configuration with AH Token
###############################################################################

tee ~/.ansible.cfg > /dev/null <<EOF
[defaults]
[galaxy]
server_list = automation_hub, validated, galaxy
[galaxy_server.automation_hub]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=$AH_TOKEN
[galaxy_server.validated]
url = https://console.redhat.com/api/automation-hub/content/validated/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token=$AH_TOKEN
[galaxy_server.galaxy]
url=https://galaxy.ansible.com/
[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF

###############################################################################
# 4. Install packages
###############################################################################

run_if_needed "Install base packages" \
    rpm -q dnf-utils \
    -- \
    dnf install -y dnf-utils git nano

###############################################################################
# 5. Clone DCC content repo (idempotent)
###############################################################################

DCC_REPO="/tmp/dcc-workshop"

if [ -d "${DCC_REPO}/.git" ]; then
    echo "INFO: ${DCC_REPO} exists, pulling latest"
    git -C "${DCC_REPO}" pull --ff-only origin master || true
else
    rm -rf "${DCC_REPO}"
    retry "Clone DCC content repo" \
        git clone -b master https://github.com/nmartins-redhat/defend-contain-comply.git "${DCC_REPO}"
fi

mkdir -p /tmp/.ansible-cp /tmp/.ansible-fact-cache
chmod 700 /tmp/.ansible-cp /tmp/.ansible-fact-cache

###############################################################################
# 6. Install Ansible collections
###############################################################################

tee /tmp/requirements.yml > /dev/null <<EOF
---
collections:
  - name: ansible.controller
  - name: ansible.posix
  - name: ansible.utils
  - name: containers.podman
  - name: community.general
  - name: redhat.rhel_system_roles
EOF

run_if_needed "Install Ansible collections" \
    bash -c 'ansible-galaxy collection list | grep -q "ansible.posix"' \
    -- \
    ansible-galaxy install -r /tmp/requirements.yml

# awx.awx fallback for ansible.controller
if ! ansible-galaxy collection list 2>/dev/null | grep -q "ansible.controller"; then
    echo "INFO: ansible.controller not found; symlinking awx.awx as ansible.controller"
    mkdir -p ~/.ansible/collections/ansible_collections/ansible
    ln -sfn ~/.ansible/collections/ansible_collections/awx/awx \
            ~/.ansible/collections/ansible_collections/ansible/controller
fi

echo ""
echo "control bootstrap phase complete"
