package auth

// Role represents a user authorization level in Gubernator.
type Role string

const (
	RoleAdmin    Role = "admin"
	RoleOperator Role = "operator"
	RoleReadOnly Role = "readonly"
)

// Permissions for fine-grained authorization.
type Permissions struct {
	CanDeployStacks      bool `json:"can_deploy_stacks"`
	CanDeleteStacks      bool `json:"can_delete_stacks"`
	CanRestartTasks      bool `json:"can_restart_tasks"`
	CanDeleteTasks       bool `json:"can_delete_tasks"`
	CanExecuteShell      bool `json:"can_execute_shell"`
	CanManageNodes       bool `json:"can_manage_nodes"`
	CanManageCaddy       bool `json:"can_manage_caddy"`
	CanManageCoreDNS     bool `json:"can_manage_coredns"`
	CanManageSecurity    bool `json:"can_manage_security"`
	CanViewObservability bool `json:"can_view_observability"`
}

// GetPermissions returns the permission set associated with a role.
func GetPermissions(r Role) Permissions {
	switch r {
	case RoleAdmin:
		return Permissions{
			CanDeployStacks:      true,
			CanDeleteStacks:      true,
			CanRestartTasks:      true,
			CanDeleteTasks:       true,
			CanExecuteShell:      true,
			CanManageNodes:       true,
			CanManageCaddy:       true,
			CanManageCoreDNS:     true,
			CanManageSecurity:    true,
			CanViewObservability: true,
		}
	case RoleOperator:
		return Permissions{
			CanDeployStacks:      true,
			CanDeleteStacks:      false,
			CanRestartTasks:      true,
			CanDeleteTasks:       false,
			CanExecuteShell:      true,
			CanManageNodes:       false,
			CanManageCaddy:       false,
			CanManageCoreDNS:     false,
			CanManageSecurity:    false,
			CanViewObservability: true,
		}
	default:
		return Permissions{
			CanDeployStacks:      false,
			CanDeleteStacks:      false,
			CanRestartTasks:      false,
			CanDeleteTasks:       false,
			CanExecuteShell:      false,
			CanManageNodes:       false,
			CanManageCaddy:       false,
			CanManageCoreDNS:     false,
			CanManageSecurity:    false,
			CanViewObservability: true,
		}
	}
}

// IsValidRole checks if the role string is recognized.
func IsValidRole(r string) bool {
	switch Role(r) {
	case RoleAdmin, RoleOperator, RoleReadOnly:
		return true
	default:
		return false
	}
}

// NormalizeRole returns a valid Role, defaulting to RoleReadOnly if unknown.
func NormalizeRole(r string) Role {
	switch Role(r) {
	case RoleAdmin:
		return RoleAdmin
	case RoleOperator:
		return RoleOperator
	case RoleReadOnly:
		return RoleReadOnly
	default:
		return RoleReadOnly
	}
}
