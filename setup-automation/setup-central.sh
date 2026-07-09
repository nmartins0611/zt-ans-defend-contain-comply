#!/bin/bash
set -euo pipefail

echo "Starting Central node setup (bootstrap phase)..."

cleanup() {
    echo "Cleaning up temporary ansible configuration..."
    rm -rf ~/.ansible.cfg
}
trap cleanup EXIT

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

###############################################################################
# 1. Validate required environment variables
###############################################################################

for var in AH_TOKEN TMM_ORG TMM_ID GUID DOMAIN; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var environment variable is not set"
        exit 1
    fi
done

###############################################################################
# 2. Environment variables
###############################################################################

export ANSIBLE_HOST_KEY_CHECKING=False
mkdir -p /root/.ansible/cp

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

dnf install -y podman python3 createrepo_c git 2>/dev/null || true

###############################################################################
# 5. Install Ansible collections for setup playbooks
###############################################################################

tee /tmp/requirements.yml > /dev/null <<EOF
---
collections:
  - name: containers.podman
  - name: ansible.posix
  - name: community.general
EOF

ansible-galaxy collection install -r /tmp/requirements.yml 2>/dev/null || true

###############################################################################
# 6. Clone DCC content repo (idempotent)
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
# 7. Deploy Splunk + OPA containers
###############################################################################

cd "${DCC_REPO}" || { echo "ERROR: Cannot cd to ${DCC_REPO}"; exit 1; }
ansible-playbook setup/deploy-central-services.yml -i inventory/workshop.yml -c local

echo ""
echo "central bootstrap phase complete"
