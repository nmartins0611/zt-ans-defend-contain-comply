package dcc.execution_policy

import rego.v1

default allow := false

authorized_users := {"security_engineer"}

allow if {
	authorized_users[input.user]
}

deny_reason := sprintf("User '%s' is not authorized for patching operations. Only security engineers may execute this workflow.", [input.user]) if {
	not allow
}

result := {
	"allow": allow,
	"reason": deny_reason,
}
