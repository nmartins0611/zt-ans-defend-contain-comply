#!/bin/bash
set -euo pipefail

echo "Starting Control node setup (configure phase)..."
export ANSIBLE_LOCALHOST_WARNING=False
export ANSIBLE_INVENTORY_UNPARSED_WARNING=False
export ANSIBLE_HOST_KEY_CHECKING=False

AAP_HOST="https://control"
AAP_USER="admin"
AAP_PASS="ansible123!"

DCC_REPO="/tmp/dcc-workshop"
cd "${DCC_REPO}" || { echo "ERROR: Cannot cd to ${DCC_REPO}"; exit 1; }

###############################################################################
# 1. Wait for AAP to be ready
###############################################################################

echo "Waiting for AAP controller to be ready..."
AAP_READY=false
for i in $(seq 1 60); do
    CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
        "${AAP_HOST}/api/controller/v2/ping/" -u "${AAP_USER}:${AAP_PASS}" 2>/dev/null)
    if [ "$CODE" = "200" ]; then
        echo "  AAP ready (attempt $i)"
        AAP_READY=true
        break
    fi
    echo "  waiting... (attempt $i, HTTP $CODE)"
    sleep 10
done

if [ "$AAP_READY" != "true" ]; then
    echo "ERROR: AAP controller did not become ready after 600s — aborting"
    exit 1
fi

###############################################################################
# 2. Generate an OAuth token for configure playbooks
###############################################################################

echo "Generating AAP OAuth token..."
CONTROLLER_OAUTH_TOKEN=$(curl -sk -X POST \
    "${AAP_HOST}/api/controller/v2/tokens/" \
    -H "Content-Type: application/json" \
    -u "${AAP_USER}:${AAP_PASS}" \
    -d '{"description":"dcc-setup-automation","application":null,"scope":"write"}' | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null)

if [ -z "${CONTROLLER_OAUTH_TOKEN}" ]; then
    echo "ERROR: Failed to generate AAP OAuth token — aborting configure phase"
    exit 1
fi
echo "  Token generated OK"
export CONTROLLER_OAUTH_TOKEN

###############################################################################
# 3. Run app server setup (from control, targeting remote hosts)
###############################################################################

ansible-playbook setup/configure-app-server.yml \
    -i inventory/workshop.yml

###############################################################################
# 4. Run DCC AAP and EDA configuration playbooks
###############################################################################

ansible-playbook setup/configure-aap.yml \
    -i inventory/workshop.yml \
    -e "controller_oauth_token_override=${CONTROLLER_OAUTH_TOKEN}"

ansible-playbook setup/configure-eda.yml \
    -i inventory/workshop.yml \
    -e "controller_oauth_token_override=${CONTROLLER_OAUTH_TOKEN}"

echo ""
echo "control configure phase complete"
