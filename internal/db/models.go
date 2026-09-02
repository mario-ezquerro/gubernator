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
	DiskUsedBytes uint64             `gorm:"-" json:"disk_used_bytes"`
	DiskTotalBytes uint64            `gorm:"-" json:"disk_total_bytes"`
	DiskFreeBytes uint64             `gorm:"-" json:"disk_free_bytes"`
	DiskPercent   float64            `gorm:"-" json:"disk_percent"`
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

// ClusterConfig holds global cluster configurations like the join token, API token, and cluster domain.
type ClusterConfig struct {
	ID            string `gorm:"primaryKey;type:varchar(50)" json:"id"`
	JoinToken     string `gorm:"type:varchar(255);not null" json:"join_token"`
	APIToken      string `gorm:"type:varchar(255)" json:"api_token"` // Bearer token for the REST API (port 4000)
	TargetVersion string `gorm:"type:varchar(50)" json:"target_version"` // Target version for cluster auto-update
	ClusterDomain string `gorm:"type:varchar(255);default:'gbnt.local'" json:"cluster_domain"` // Base internal DNS domain (default: "gbnt.local")
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
	Command           string    `gorm:"type:text" json:"command"`
	CpuLimit          string    `gorm:"type:varchar(50)" json:"cpu_limit"`
	MemoryLimit       string    `gorm:"type:varchar(50)" json:"memory_limit"`
	CpuReservation    string    `gorm:"type:varchar(50)" json:"cpu_reservation"`
	MemoryReservation string    `gorm:"type:varchar(50)" json:"memory_reservation"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
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
	ID                string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	ServiceID         string    `gorm:"type:varchar(255);index;not null" json:"service_id"`
	NodeID            string    `gorm:"type:varchar(255);index;not null" json:"node_id"`
	Status            string    `gorm:"type:varchar(50);not null" json:"status"` // "pending", "running", "dead"
	ContainerIP       string    `gorm:"type:varchar(50)" json:"container_ip"`
	ContainerName     string    `gorm:"type:varchar(255)" json:"container_name"`
	CpuLimit          string    `gorm:"type:varchar(50)" json:"cpu_limit"`
	MemoryLimit       string    `gorm:"type:varchar(50)" json:"memory_limit"`
	CpuReservation    string    `gorm:"type:varchar(50)" json:"cpu_reservation"`
	MemoryReservation string    `gorm:"type:varchar(50)" json:"memory_reservation"`
	CpuPercent        float64   `gorm:"-" json:"cpu_percent"`
	MemUsedBytes      uint64    `gorm:"-" json:"mem_used_bytes"`
	Error             string    `gorm:"type:text" json:"error"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
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
	Driver        string    `gorm:"type:varchar(50);default:'local'" json:"driver"`
	SourcePath    string    `gorm:"type:text;not null" json:"source_path"`
	TargetPath    string    `gorm:"type:text" json:"target_path"`
	StackID       string    `gorm:"type:varchar(255);index" json:"stack_id"`
	StackName     string    `gorm:"type:varchar(255)" json:"stack_name"`
	ServiceName   string    `gorm:"type:varchar(255)" json:"service_name"`
	NodeID        string    `gorm:"type:varchar(255);default:'all'" json:"node_id"`
	NodeIP        string    `gorm:"type:varchar(50)" json:"node_ip"`
	NodeHostname  string    `gorm:"type:varchar(100)" json:"node_hostname"`
	NodeRole      string    `gorm:"type:varchar(50)" json:"node_role"`
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
	DestinationPath string     `gorm:"type:text" json:"destination_path"` // Destination directory for backup archives
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

// StorageMount represents a managed /etc/fstab filesystem mount (NFS, S3, Samba, GlusterFS, etc.).
type StorageMount struct {
	ID              string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name            string    `gorm:"type:varchar(255);not null" json:"name"`
	Device          string    `gorm:"type:text;not null" json:"device"`         // e.g. "192.168.1.50:/share", "//nas/samba", "s3fs#my-bucket"
	MountPoint      string    `gorm:"type:text;not null" json:"mount_point"`    // e.g. "/var/contenedores", "/mnt/s3-models"
	FSType          string    `gorm:"type:varchar(50);not null" json:"fs_type"` // "nfs", "nfs4", "cifs", "fuse.s3fs", "rclone", "ext4", "glusterfs"
	Options         string    `gorm:"type:text" json:"options"`                 // e.g. "rw,_netdev,rsize=1048576"
	Dump            int       `gorm:"default:0" json:"dump"`
	Pass            int       `gorm:"default:0" json:"pass"`
	TargetNode      string    `gorm:"type:varchar(255);default:'all'" json:"target_node"` // "all" or specific NodeID
	CredentialsFile string    `gorm:"type:text" json:"credentials_file,omitempty"`
	AutoMount       bool      `gorm:"default:true" json:"auto_mount"`
	Status          string    `gorm:"type:varchar(50);default:'unmounted'" json:"status"` // "mounted", "unmounted", "error"
	IsActive        bool      `gorm:"default:true" json:"is_active"`
	ErrorMessage    string    `gorm:"type:text" json:"error_message,omitempty"`
	Description     string    `gorm:"type:text" json:"description"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// ManagedGlusterVolume persists cluster GlusterFS configuration.
type ManagedGlusterVolume struct {
	Name         string    `gorm:"primaryKey;type:varchar(100)" json:"name"`
	Type         string    `gorm:"type:varchar(50);default:'Replicate'" json:"type"`
	ReplicaCount int       `gorm:"default:3" json:"replica_count"`
	ArbiterCount int       `gorm:"default:0" json:"arbiter_count"`
	BricksJSON   string    `gorm:"type:text" json:"bricks_json"`
	MountPoint   string    `gorm:"type:text" json:"mount_point"`
	AutoMounted  bool      `gorm:"default:true" json:"auto_mounted"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// DirectoryEntry represents a file or folder discovered in a storage directory.
type DirectoryEntry struct {
	Name          string    `json:"name"`
	Path          string    `json:"path"`
	IsDir         bool      `json:"is_dir"`
	SizeBytes     int64     `json:"size_bytes"`
	SizeFormatted string    `json:"size_formatted"`
	Permissions   string    `json:"permissions"`
	ModTime       time.Time `json:"mod_time"`
	NodeID        string    `json:"node_id,omitempty"`
}

// SecurityPolicy defines the cluster admission gatekeeper rules.
type SecurityPolicy struct {
	ID                string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name              string    `gorm:"type:varchar(255);not null" json:"name"`
	EnforceSignatures string    `gorm:"type:varchar(50);default:'audit'" json:"enforce_signatures"` // 'disabled', 'audit', 'enforce'
	BlockCVESeverity  string    `gorm:"type:varchar(50);default:'none'" json:"block_cve_severity"`  // 'none', 'critical', 'high', 'medium'
	AllowUnfixedCVE   bool      `gorm:"default:true" json:"allow_unfixed_cve"`
	TrustedRegistries string    `gorm:"type:text" json:"trusted_registries"` // JSON array
	UpdatedAt         time.Time `json:"updated_at"`
}

// TrustedSigningKey represents a trusted public signing key for Cosign image verification.
type TrustedSigningKey struct {
	ID            string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	Name          string    `gorm:"type:varchar(255);not null" json:"name"`
	PublicKeyPEM  string    `gorm:"type:text;not null" json:"public_key_pem"`
	PrivateKeyPEM string    `gorm:"type:text" json:"-"`
	HasPrivateKey bool      `gorm:"-" json:"has_private_key"`
	KeyType       string    `gorm:"type:varchar(50);default:'cosign-ecdsa'" json:"key_type"`
	IsDefault     bool      `gorm:"default:false" json:"is_default"`
	CreatedAt     time.Time `json:"created_at"`
}

// ImageScan represents an image vulnerability scan report.
type ImageScan struct {
	ID              string     `gorm:"primaryKey;type:varchar(50)" json:"id"`
	ImageName       string     `gorm:"type:varchar(255);not null;index" json:"image_name"`
	ImageDigest     string     `gorm:"type:varchar(255)" json:"image_digest"`
	ScannedAt       time.Time  `json:"scanned_at"`
	CriticalCount   int        `gorm:"default:0" json:"critical_count"`
	HighCount       int        `gorm:"default:0" json:"high_count"`
	MediumCount     int        `gorm:"default:0" json:"medium_count"`
	LowCount        int        `gorm:"default:0" json:"low_count"`
	TotalCount      int        `gorm:"default:0" json:"total_count"`
	SignatureStatus string     `gorm:"type:varchar(50);default:'unsigned'" json:"signature_status"` // 'verified', 'unsigned', 'invalid'
	SignatureSigner string     `gorm:"type:varchar(255)" json:"signature_signer,omitempty"`
	SignedAt        *time.Time `json:"signed_at,omitempty"`
	HostsRaw        []byte     `gorm:"type:json" json:"-"`
	Hosts           []string   `gorm:"-" json:"hosts"`
	ServicesRaw     []byte     `gorm:"type:json" json:"-"`
	Services        []string   `gorm:"-" json:"services"`
	InUse           bool       `gorm:"-" json:"in_use"`
}

func (s *ImageScan) BeforeSave(tx *gorm.DB) (err error) {
	marshalField := func(v interface{}, nilVal []byte) []byte {
		if v == nil {
			return nilVal
		}
		b, _ := json.Marshal(v)
		return b
	}
	s.HostsRaw = marshalField(s.Hosts, []byte("[]"))
	s.ServicesRaw = marshalField(s.Services, []byte("[]"))
	return nil
}

func (s *ImageScan) AfterFind(tx *gorm.DB) (err error) {
	if len(s.HostsRaw) > 0 {
		json.Unmarshal(s.HostsRaw, &s.Hosts)
	}
	if s.Hosts == nil {
		s.Hosts = make([]string, 0)
	}
	if len(s.ServicesRaw) > 0 {
		json.Unmarshal(s.ServicesRaw, &s.Services)
	}
	if s.Services == nil {
		s.Services = make([]string, 0)
	}
	return nil
}

// ImageVulnerability represents an individual CVE found during an image scan.
type ImageVulnerability struct {
	ID               string   `gorm:"primaryKey;type:varchar(50)" json:"id"`
	ScanID           string   `gorm:"type:varchar(50);index;not null" json:"scan_id"`
	CVEID            string   `gorm:"type:varchar(50);index;not null" json:"cve_id"`
	PackageName      string   `gorm:"type:varchar(255);not null" json:"package_name"`
	InstalledVersion string   `gorm:"type:varchar(100);not null" json:"installed_version"`
	FixedVersion     string   `gorm:"type:varchar(100)" json:"fixed_version,omitempty"`
	Severity         string   `gorm:"type:varchar(50);not null" json:"severity"` // 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'
	CVSSScore        float64  `json:"cvss_score"`
	Title            string   `gorm:"type:varchar(255)" json:"title"`
	Description      string   `gorm:"type:text" json:"description"`
	PrimaryURL       string   `gorm:"type:varchar(1024)" json:"primary_url"`
}

// ImageSBOM represents a Software Bill of Materials for a container image.
type ImageSBOM struct {
	ID           string    `gorm:"primaryKey;type:varchar(50)" json:"id"`
	ScanID       string    `gorm:"type:varchar(50);index;not null" json:"scan_id"`
	ImageName    string    `gorm:"type:varchar(255);not null" json:"image_name"`
	Format       string    `gorm:"type:varchar(50);default:'cyclonedx-json'" json:"format"`
	PackageCount int       `gorm:"default:0" json:"package_count"`
	RawSBOMJSON  string    `gorm:"type:longtext" json:"raw_sbom_json"`
	GeneratedAt  time.Time `json:"generated_at"`
}


