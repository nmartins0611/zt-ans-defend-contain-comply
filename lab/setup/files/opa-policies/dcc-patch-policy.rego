package dcc.patch_policy

import rego.v1

default allow_patch := false
default maintenance_window_ok := false
default backup_current := false
default disk_space_ok := false
default service_healthy := false
default user_authorized := false

authorized_patch_users := {"security_engineer"}

maintenance_window_ok if {
	hour := to_number(input.current_hour)
	hour >= 6
	hour < 22
}

backup_current if {
	to_number(input.backup_age_hours) < 24
}

disk_space_ok if {
	to_number(input.free_disk_gb) > 2
}

service_healthy if {
	input.service_state == "active"
}

user_authorized if {
	authorized_patch_users[input.requesting_user]
}

gate_results := {
	"maintenance_window": {"pass": maintenance_window_ok, "description": "Current time within maintenance window"},
	"backup_current": {"pass": backup_current, "description": "Backup exists within 24 hours"},
	"disk_space": {"pass": disk_space_ok, "description": "More than 2GB free on root filesystem"},
	"service_health": {"pass": service_healthy, "description": "Target service is running"},
	"user_authorized": {"pass": user_authorized, "description": sprintf("User '%s' is authorized for patching operations", [input.requesting_user])},
}

failed_gates contains name if {
	some name, result in gate_results
	not result.pass
}

allow_patch if {
	count(failed_gates) == 0
}

result := {
	"allow_patch": allow_patch,
	"gates": gate_results,
	"failed_gates": failed_gates,
	"total_gates": count(gate_results),
	"passed_gates": count(gate_results) - count(failed_gates),
}
