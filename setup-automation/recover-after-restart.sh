#!/bin/bash
# recover-after-restart.sh — Restore DCC lab runtime state after a stop/start.
#
# Checks and restarts services that may not survive a VM reboot despite
# systemd enablement (Vault unseal, Podman containers, errata repo).
#
# Usage:
#   sudo bash recover-after-restart.sh

set -euo pipefail

echo "DCC Workshop -- Recovery after restart"

###############################################################################
# 1. Vault unseal (runs on vault host via SSH)
###############################################################################

echo "Checking Vault seal status..."
if command -v vault &>/dev/null; then
    if vault status -address=http://vault:8200 2>/dev/null | grep -q "Sealed.*true"; then
        echo "  Vault is sealed -- attempting unseal..."
        echo "  NOTE: Manual unseal keys required. Run:"
        echo "    vault operator unseal -address=http://vault:8200"
    else
        echo "  Vault is unsealed or unreachable"
    fi
else
    echo "  SKIP: vault CLI not available on this host"
fi

###############################################################################
# 2. Splunk container
###############################################################################

echo "Checking Splunk container..."
if podman container exists splunk 2>/dev/null; then
    if ! podman inspect splunk --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
        echo "  Starting Splunk container..."
        systemctl start container-splunk 2>/dev/null || podman start splunk
    else
        echo "  Splunk is running"
    fi
else
    echo "  SKIP: Splunk container does not exist"
fi

###############################################################################
# 3. OPA container
###############################################################################

echo "Checking OPA container..."
if podman container exists opa 2>/dev/null; then
    if ! podman inspect opa --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
        echo "  Starting OPA container..."
        systemctl start container-opa 2>/dev/null || podman start opa
    else
        echo "  OPA is running"
    fi
else
    echo "  SKIP: OPA container does not exist"
fi

###############################################################################
# 4. Errata repo HTTP server
###############################################################################

echo "Checking errata repo HTTP server..."
if systemctl is-enabled dcc-errata-repo &>/dev/null; then
    if ! systemctl is-active dcc-errata-repo &>/dev/null; then
        echo "  Starting errata repo HTTP server..."
        systemctl start dcc-errata-repo
    else
        echo "  Errata repo is running"
    fi
else
    echo "  SKIP: dcc-errata-repo service not found"
fi

###############################################################################
# 5. httpd on app server (rhel01)
###############################################################################

echo "Checking httpd on app server..."
if systemctl is-enabled httpd &>/dev/null; then
    if ! systemctl is-active httpd &>/dev/null; then
        echo "  Starting httpd..."
        systemctl start httpd
    else
        echo "  httpd is running"
    fi
fi

echo ""
echo "Recovery complete."
