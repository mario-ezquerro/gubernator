package db

import (
	"encoding/json"
	"time"

	"gorm.io/gorm"
)

// Node represents a server (Centurion) in the Gubernator cluster.
type Node struct {
	ID        string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	IP        string    `gorm:"type:varchar(255);not null" json:"ip"`
	Role      string    `gorm:"type:varchar(50);not null" json:"role"`     // e.g., "manager", "worker"
	Status    string    `gorm:"type:varchar(50);not null" json:"status"`   // e.g., "active", "down", "drain"
	LabelsRaw []byte    `gorm:"type:json" json:"-"`                        // Raw JSON bytes for SQLite storage
	Labels    map[string]string `gorm:"-" json:"labels"`                   // Parsed labels for the application
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
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
		return json.Unmarshal(n.LabelsRaw, &n.Labels)
	}
	n.Labels = make(map[string]string)
	return nil
}

// ClusterConfig holds global cluster configurations like the join token.
type ClusterConfig struct {
	ID        string `gorm:"primaryKey;type:varchar(50)"`
	JoinToken string `gorm:"type:varchar(255);not null"`
}

// Stack represents a deployed docker-compose environment.
type Stack struct {
	ID             string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	Name           string    `gorm:"type:varchar(255);not null" json:"name"`
	RawComposeFile string    `gorm:"type:text" json:"-"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// Service represents a specific service defined inside a Stack.
type Service struct {
	ID             string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	StackID        string    `gorm:"type:varchar(255);index;not null" json:"stack_id"`
	Name           string    `gorm:"type:varchar(255);not null" json:"name"`
	Image          string    `gorm:"type:varchar(255);not null" json:"image"`
	DesiredReplicas int      `json:"desired_replicas"`
	ConstraintsRaw []byte    `gorm:"type:json" json:"-"`
	Constraints    []string  `gorm:"-" json:"constraints"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// Task represents a running container instance of a Service assigned to a Node.
type Task struct {
	ID          string    `gorm:"primaryKey;type:varchar(255)" json:"id"`
	ServiceID   string    `gorm:"type:varchar(255);index;not null" json:"service_id"`
	NodeID      string    `gorm:"type:varchar(255);index;not null" json:"node_id"`
	Status      string    `gorm:"type:varchar(50);not null" json:"status"` // "pending", "running", "dead"
	ContainerIP string    `gorm:"type:varchar(50)" json:"container_ip"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Hooks for Service to handle JSON serialization of Constraints
func (s *Service) BeforeSave(tx *gorm.DB) (err error) {
	if s.Constraints == nil {
		s.ConstraintsRaw = []byte("[]")
		return nil
	}
	bytes, err := json.Marshal(s.Constraints)
	if err == nil {
		s.ConstraintsRaw = bytes
	}
	return err
}

func (s *Service) AfterFind(tx *gorm.DB) (err error) {
	if len(s.ConstraintsRaw) > 0 {
		return json.Unmarshal(s.ConstraintsRaw, &s.Constraints)
	}
	s.Constraints = make([]string, 0)
	return nil
}
