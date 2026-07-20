package aap.gateway

import rego.v1

# AAP 2.6 Platform Policy — evaluated by the controller BEFORE a job launches.
#
# Key input fields from AAP:
#   input.name                      — job/workflow template name
#   input.created_by.username       — who launched the job
#   input.created_by.is_superuser   — platform superuser flag
#
# Output contract: {"allowed": bool, "violations": [strings]}
#
# Enforcement point: Organisation → policy = "aap/gateway/decision"

default decision := {"allowed": true, "violations": []}

_authorized_patch_users := {"security_engineer"}

_template_name := lower(input.name)

_is_patching_template if contains(_template_name, "patch")

decision := {
	"allowed": false,
	"violations": [sprintf(
		"user '%s' is not authorized for patching operations (requires one of: %v)",
		[input.created_by.username, _authorized_patch_users],
	)],
} if {
	_is_patching_template
	not _authorized_patch_users[input.created_by.username]
}
