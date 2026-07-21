package dcc.compliance

import rego.v1

# System compliance baselines for the DCC workshop.
# Input: JSON object with host facts collected by the compliance-audit playbook.

default compliant := false
default selinux_enforcing := false
default firewall_active := false
default ssh_root_login_disabled := false
default ssh_x11_forwarding_disabled := false
default ssh_max_auth_tries_ok := false
default ssh_client_alive_set := false
default sysctl_accept_redirects_disabled := false
default sysctl_send_redirects_disabled := false
default sysctl_aslr_enabled := false
default passwd_permissions_ok := false
default shadow_permissions_ok := false
default no_unnecessary_services := false
default no_open_cves := false

# ── SELinux ─────────────────────────────────────────────────────────

selinux_enforcing if {
	input.selinux_mode == "Enforcing"
}

# ── Firewall ────────────────────────────────────────────────────────

firewall_active if {
	input.firewall_active == true
}

# ── SSH Hardening ───────────────────────────────────────────────────

ssh_root_login_disabled if {
	input.ssh_permit_root_login == "no"
}

ssh_x11_forwarding_disabled if {
	input.ssh_x11_forwarding == "no"
}

ssh_max_auth_tries_ok if {
	input.ssh_max_auth_tries <= 4
}

ssh_client_alive_set if {
	input.ssh_client_alive_interval > 0
	input.ssh_client_alive_interval <= 300
}

# ── Kernel Parameters ───────────────────────────────────────────────

sysctl_accept_redirects_disabled if {
	input.sysctl_accept_redirects == 0
}

sysctl_send_redirects_disabled if {
	input.sysctl_send_redirects == 0
}

sysctl_aslr_enabled if {
	input.sysctl_randomize_va_space == 2
}

# ── File Permissions ────────────────────────────────────────────────

passwd_permissions_ok if {
	input.passwd_mode <= 644
}

shadow_permissions_ok if {
	input.shadow_mode <= 640
}

# ── Services ────────────────────────────────────────────────────────

no_unnecessary_services if {
	input.rpcbind_enabled == false
}

# ── Vulnerability State ─────────────────────────────────────────────

no_open_cves if {
	count(input.open_cves) == 0
}

# ── Control Definitions ─────────────────────────────────────────────

controls := [
	{"id": "SEL-01", "name": "SELinux enforcing", "category": "selinux", "pass": selinux_enforcing},
	{"id": "FW-01", "name": "Firewall active", "category": "firewall", "pass": firewall_active},
	{"id": "SSH-01", "name": "Root login disabled", "category": "ssh", "pass": ssh_root_login_disabled},
	{"id": "SSH-02", "name": "X11 forwarding disabled", "category": "ssh", "pass": ssh_x11_forwarding_disabled},
	{"id": "SSH-03", "name": "Max auth tries <= 4", "category": "ssh", "pass": ssh_max_auth_tries_ok},
	{"id": "SSH-04", "name": "Client alive interval set", "category": "ssh", "pass": ssh_client_alive_set},
	{"id": "KERN-01", "name": "ICMP redirects disabled", "category": "kernel", "pass": sysctl_accept_redirects_disabled},
	{"id": "KERN-02", "name": "Send redirects disabled", "category": "kernel", "pass": sysctl_send_redirects_disabled},
	{"id": "KERN-03", "name": "ASLR enabled", "category": "kernel", "pass": sysctl_aslr_enabled},
	{"id": "FILE-01", "name": "/etc/passwd permissions <= 644", "category": "files", "pass": passwd_permissions_ok},
	{"id": "FILE-02", "name": "/etc/shadow permissions <= 640", "category": "files", "pass": shadow_permissions_ok},
	{"id": "SVC-01", "name": "No unnecessary services (rpcbind)", "category": "services", "pass": no_unnecessary_services},
	{"id": "CVE-01", "name": "No open CVEs", "category": "vulnerability", "pass": no_open_cves},
]

passed_controls := [c | some c in controls; c.pass == true]
failed_controls := [c | some c in controls; c.pass == false]

compliant if {
	count(failed_controls) == 0
}

result := {
	"compliant": compliant,
	"controls": controls,
	"total": count(controls),
	"passed": count(passed_controls),
	"failed": count(failed_controls),
}
