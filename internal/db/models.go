package db

import (
	"encoding/json"
	"time"

	"gorm.io/gorm"
)

// Node represents a server (Centurion) in the Gubernator cluster.
type Node struct {
	ID        string            `gorm:"primaryKey;type:varchar(255)" json:"id"`
	IP        string            `gorm:"type:varchar(255);not null" json:"ip"`
	Role      string            `gorm:"type:varchar(50);not null" json:"role"`   // e.g., "manager", "worker"
	Status    string            `gorm:"type:varchar(50);not null" json:"status"` // e.g., "active", "down", "drain"
	LabelsRaw   []byte            `gorm:"type:json" json:"-"`                      // Raw JSON bytes for SQLite storage
	Labels      map[string]string `gorm:"-" json:"labels"`                         // Parsed labels for the application
	CpuPercent    float64            `gorm:"-" json:"cpu_percent"`
	MemUsedBytes  uint64             `gorm:"-" json:"mem_used_bytes"`
	MemTotalBytes uint64             `gorm:"-" json:"mem_total_bytes"`
	MemPercent    float64            `gorm:"-" json:"mem_percent"`
	NetBps        float64            `gorm:"-" json:"net_bps"`
	CaddyStatus   string             `gorm:"type:text" json:"caddy_status"`
	Caddyfile     string             `gorm:"type:text" json:"caddyfile"`
	AuthMismatch  bool               `gorm:"-" json:"auth_mismatch"`
	CreatedAt     time.Time          `json:"created_at"`
	UpdatedAt     time.Time          `json:"updated_at"`
}

// BeforeSave hook to marshal Labels into LabelsRaw before saving to DB
func (n *Node) BeforeSave(tx *gorm.DB) (err error) {
	if n.Labels == nil {
		n.LabelsRaw = []byte("{}")
		return nil
	}
	bytes, err := json.Marshal(n.Labels)
	if err == nil {
		n.LabelsRaw = bytes
	}
	return err
}

// AfterFind hook to unmarshal LabelsRaw into Labels after reading from DB
func (n *Node) AfterFind(tx *gorm.DB) (err error) {
	if len(n.LabelsRaw) > 0 {
		err = json.Unmarshal(n.LabelsRaw, &n.Labels)
	} else {
		n.Labels = make(map[string]string)
	}
	if err != nil {
		return err
	}
	if n.Labels == nil {
		n.Labels = make(map[string]string)
	}
	// Dynamically populate/ensure fixed system labels are present
	n.Labels["gbnt.node.role"] = n.Role
	if _, exists := n.Labels["gbnt.node.arch"]; !exists || n.Labels["gbnt.node.arch"] == "" {
		n.Labels["gbnt.node.arch"] = DetectArch()
	}
	return nil
}

// ClusterConfig holds global cluster configurations like the join token and API token.
type ClusterConfig struct {
	ID            string `gorm:"primaryKey;type:varchar(50)"`
	JoinToken     string `gorm:"type:varchar(255);not null"`
	APIToken      string `gorm:"type:varchar(255)"` // Bearer token for the REST API (port 4000)
	TargetVersion string `gorm:"type:varchar(50)"`  // Target version for cluster auto-update
}

// Stack represents a deployed docker-compose environment.
type Stack struct {
	ID             string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	Name           string    `gorm:"type:varchar(255);not null" json:"name"`
	RawComposeFile string    `gorm:"type:text" json:"raw_compose_file"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// Service represents a specific service defined inside a Stack.
type Service struct {
	ID              string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	StackID         string    `gorm:"type:varchar(255);index;not null" json:"stack_id"`
	Name            string    `gorm:"type:varchar(255);not null" json:"name"`
	Image           string    `gorm:"type:varchar(255);not null" json:"image"`
	DesiredReplicas int       `json:"desired_replicas"`
	ConstraintsRaw  []byte    `gorm:"type:json" json:"-"`
	Constraints     []string  `gorm:"-" json:"constraints"`
	PortsRaw        []byte    `gorm:"type:json" json:"-"`
	Ports           []string  `gorm:"-" json:"ports"` // e.g. ["8080:80", "443:443"]
	EnvRaw          []byte    `gorm:"type:json" json:"-"`
	Env             []string  `gorm:"-" json:"env"` // e.g. ["FOO=bar"]
	VolumesRaw      []byte    `gorm:"type:json" json:"-"`
	Volumes         []string  `gorm:"-" json:"volumes"` // e.g. ["/host:/container"]
	Command         string    `gorm:"type:text" json:"command"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// SLONotificationConfig stores alert delivery channels (Email/SMTP, Webhook) for SLO failures.
type SLONotificationConfig struct {
	ID                 string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	EnableEmail        bool      `json:"enable_email"`
	SMTPHost           string    `gorm:"type:varchar(255)" json:"smtp_host"`
	SMTPPort           int       `json:"smtp_port"`
	SMTPUser           string    `gorm:"type:varchar(255)" json:"smtp_user"`
	SMTPPass           string    `gorm:"type:varchar(255)" json:"smtp_pass"`
	FromEmail          string    `gorm:"type:varchar(255)" json:"from_email"`
	ToEmail            string    `gorm:"type:varchar(255)" json:"to_email"`
	EnableWebhook      bool      `json:"enable_webhook"`
	WebhookURL         string    `gorm:"type:varchar(1024)" json:"webhook_url"`
	NotifyOnExhaustion bool      `json:"notify_on_exhaustion"`
	NotifyOnBurn       bool      `json:"notify_on_burn"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// Task represents a running container instance of a Service assigned to a Node.
type Task struct {
	ID            string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	ServiceID     string    `gorm:"type:varchar(255);index;not null" json:"service_id"`
	NodeID        string    `gorm:"type:varchar(255);index;not null" json:"node_id"`
	Status        string    `gorm:"type:varchar(50);not null" json:"status"` // "pending", "running", "dead"
	ContainerIP   string    `gorm:"type:varchar(50)" json:"container_ip"`
	ContainerName string    `gorm:"type:varchar(255)" json:"container_name"`
	Error         string    `gorm:"type:text" json:"error"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

func (s *Service) BeforeSave(tx *gorm.DB) (err error) {
	marshalField := func(v interface{}, nilVal []byte) []byte {
		if v == nil {
			return nilVal
		}
		b, _ := json.Marshal(v)
		return b
	}
	s.ConstraintsRaw = marshalField(s.Constraints, []byte("[]"))
	s.PortsRaw = marshalField(s.Ports, []byte("[]"))
	s.EnvRaw = marshalField(s.Env, []byte("[]"))
	s.VolumesRaw = marshalField(s.Volumes, []byte("[]"))
	return nil
}

func (s *Service) AfterFind(tx *gorm.DB) (err error) {
	unmarshal := func(raw []byte, out interface{}) {
		if len(raw) > 0 {
			json.Unmarshal(raw, out)
		}
	}
	unmarshal(s.ConstraintsRaw, &s.Constraints)
	unmarshal(s.PortsRaw, &s.Ports)
	unmarshal(s.EnvRaw, &s.Env)
	unmarshal(s.VolumesRaw, &s.Volumes)
	if s.Constraints == nil {
		s.Constraints = make([]string, 0)
	}
	return nil
}

// CustomDNSRecord represents a static user-configured DNS entry in CoreDNS.
type CustomDNSRecord struct {
	ID         string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	Domain     string    `gorm:"type:varchar(255);not null;index" json:"domain"`
	IP         string    `gorm:"type:varchar(255);not null" json:"ip"`
	RecordType string    `gorm:"type:varchar(10);not null;default:'A'" json:"record_type"` // A, AAAA, CNAME, TXT, PTR
	TTL        int       `gorm:"default:60" json:"ttl"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// LDAPConfig represents an Active Directory or LDAP identity provider.
type LDAPConfig struct {
	ID                 string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name               string    `gorm:"type:varchar(255);not null" json:"name"`
	Enabled            bool      `gorm:"default:true" json:"enabled"`
	Host               string    `gorm:"type:varchar(255);not null" json:"host"`
	Port               int       `gorm:"default:389" json:"port"`
	Security           string    `gorm:"type:varchar(50);default:'none'" json:"security"` // none, tls (LDAPS), starttls
	InsecureSkipVerify bool      `gorm:"default:false" json:"insecure_skip_verify"`
	BindDN             string    `gorm:"type:varchar(255)" json:"bind_dn"`
	BindPassword       string    `gorm:"type:varchar(255)" json:"bind_password"`
	BaseDN             string    `gorm:"type:varchar(255);not null" json:"base_dn"`
	UserFilter         string    `gorm:"type:varchar(255);default:'(&(objectClass=user)(sAMAccountName=%s))'" json:"user_filter"`
	UserAttr           string    `gorm:"type:varchar(50);default:'sAMAccountName'" json:"user_attr"` // sAMAccountName, uid, mail
	GroupBaseDN        string    `gorm:"type:varchar(255)" json:"group_base_dn"`
	GroupFilter        string    `gorm:"type:varchar(255);default:'(&(objectClass=group)(member=%s))'" json:"group_filter"`
	AdminGroupDN       string    `gorm:"type:varchar(255)" json:"admin_group_dn"`
	OperatorGroupDN    string    `gorm:"type:varchar(255)" json:"operator_group_dn"`
	ReadOnlyGroupDN    string    `gorm:"type:varchar(255)" json:"readonly_group_dn"`
	DefaultRole        string    `gorm:"type:varchar(50);default:'readonly'" json:"default_role"` // admin, operator, readonly, none
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// LocalUser represents a local user account stored in the Gubernator DB.
type LocalUser struct {
	ID           string     `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Username     string     `gorm:"type:varchar(100);uniqueIndex;not null" json:"username"`
	PasswordHash string     `gorm:"type:varchar(255);not null" json:"-"`
	DisplayName  string     `gorm:"type:varchar(255)" json:"display_name"`
	Email        string     `gorm:"type:varchar(255)" json:"email"`
	Role         string     `gorm:"type:varchar(50);default:'readonly'" json:"role"` // admin, operator, readonly
	Enabled      bool       `gorm:"default:true" json:"enabled"`
	LastLogin    *time.Time `json:"last_login,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// AuditLog represents a security event or user access log entry.
type AuditLog struct {
	ID        string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Timestamp time.Time `gorm:"index;not null" json:"timestamp"`
	Username  string    `gorm:"type:varchar(100);index;not null" json:"username"`
	Provider  string    `gorm:"type:varchar(50);default:'LOCAL'" json:"provider"` // LOCAL, ACTIVE_DIRECTORY
	IPAddress string    `gorm:"type:varchar(50)" json:"ip_address"`
	Action    string    `gorm:"type:varchar(100);index;not null" json:"action"` // LOGIN_SUCCESS, LOGIN_FAILED, PASSWORD_CHANGE, USER_CREATE, USER_UPDATE, USER_DELETE
	Status    string    `gorm:"type:varchar(50);default:'SUCCESS'" json:"status"` // SUCCESS, FAILURE
	Details   string    `gorm:"type:text" json:"details"`
}

// StorageVolume represents a discovered persistent volume or bind mount.
type StorageVolume struct {
	ID            string    `gorm:"primaryKey;type:varchar(100)" json:"id"`
	Name          string    `gorm:"type:varchar(255);not null" json:"name"`
	Type          string    `gorm:"type:varchar(50);not null" json:"type"` // "shared_pool", "docker_named", "host_bind"
	SourcePath    string    `gorm:"type:text;not null" json:"source_path"`
	TargetPath    string    `gorm:"type:text" json:"target_path"`
	StackID       string    `gorm:"type:varchar(255);index" json:"stack_id"`
	StackName     string    `gorm:"type:varchar(255)" json:"stack_name"`
	ServiceName   string    `gorm:"type:varchar(255)" json:"service_name"`
	NodeID        string    `gorm:"type:varchar(255);default:'all'" json:"node_id"`
	SizeBytes     int64     `json:"size_bytes"`
	SizeFormatted string    `gorm:"-" json:"size_formatted"`
	IsShared      bool      `json:"is_shared"`
	LastScannedAt time.Time `json:"last_scanned_at"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// Backup represents a point-in-time compressed archive of a volume or stack.
type Backup struct {
	ID            string     `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name          string     `gorm:"type:varchar(255);not null" json:"name"`
	StackID       string     `gorm:"type:varchar(255);index" json:"stack_id"`
	StackName     string     `gorm:"type:varchar(255)" json:"stack_name"`
	VolumeName    string     `gorm:"type:varchar(255)" json:"volume_name"`
	SourcePath    string     `gorm:"type:text" json:"source_path"`
	FilePath      string     `gorm:"type:text;not null" json:"file_path"`
	SizeBytes     int64      `json:"size_bytes"`
	SizeFormatted string     `gorm:"-" json:"size_formatted"`
	SHA256        string     `gorm:"type:varchar(64)" json:"sha256"`
	Status        string     `gorm:"type:varchar(50);default:'completed'" json:"status"` // completed, failed, in_progress
	IsScheduled   bool       `json:"is_scheduled"`
	ScheduleID    string     `gorm:"type:varchar(50)" json:"schedule_id"`
	ErrorMessage  string     `gorm:"type:text" json:"error_message,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
}

// BackupSchedule defines an automated periodic backup policy.
type BackupSchedule struct {
	ID              string     `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name            string     `gorm:"type:varchar(255);not null" json:"name"`
	CronExpression  string     `gorm:"type:varchar(100);not null" json:"cron_expression"` // e.g. "0 3 * * *" (Daily 3 AM)
	TargetType      string     `gorm:"type:varchar(50);default:'stack'" json:"target_type"` // "stack", "volume", "all"
	TargetID        string     `gorm:"type:varchar(255)" json:"target_id"` // StackID, VolumeName, or "all"
	TargetName      string     `gorm:"type:varchar(255)" json:"target_name"`
	RetentionCount  int        `gorm:"default:7" json:"retention_count"` // Keep last N backups
	PauseContainers bool       `gorm:"default:true" json:"pause_containers"`
	Enabled         bool       `gorm:"default:true" json:"enabled"`
	LastRunAt       *time.Time `json:"last_run_at,omitempty"`
	NextRunAt       *time.Time `json:"next_run_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

// StoragePool represents a shared filesystem storage mount.
type StoragePool struct {
	ID        string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name      string    `gorm:"type:varchar(255);not null" json:"name"`
	Path      string    `gorm:"type:text;not null" json:"path"` // e.g. "/var/contenedores"
	FSType    string    `gorm:"type:varchar(50)" json:"fs_type"` // nfs, glusterfs, local, etc.
	IsActive  bool      `gorm:"default:true" json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

