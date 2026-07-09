#!/bin/bash
set -euo pipefail

echo "Starting Central node setup (configure phase)..."

export ANSIBLE_HOST_KEY_CHECKING=False

###############################################################################
# Run DCC setup playbooks from the content repo
###############################################################################

DCC_REPO="/tmp/dcc-workshop"
cd "${DCC_REPO}" || { echo "ERROR: Cannot cd to ${DCC_REPO}"; exit 1; }

ansible-playbook setup/configure-errata-repo.yml -i inventory/workshop.yml -c local
ansible-playbook setup/configure-splunk-alerts.yml -i inventory/workshop.yml -c local

echo ""
echo "central configure phase complete"
