package examples

import (
	"embed"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

//go:embed data/*
var embeddedExamples embed.FS

// DeployStackFn is injected by the API orchestrator to deploy stacks without circular imports.
var DeployStackFn func(name, composeRaw, targetNode string) (*db.Stack, error)

// POCExample represents a production blueprint / POC example packaged with Gubernator.
type POCExample struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Category    string   `json:"category"` // "Web & Ingress", "Database & CMS", "SRE & Observability", "AI & Data Science", "Automation"
	Description string   `json:"description"`
	Filename    string   `json:"filename"`
	DefaultStack string  `json:"default_stack"`
	Services    []string `json:"services"`
	ComposeRaw  string   `json:"compose_raw"`
	Icon        string   `json:"icon"`
	Tags        []string `json:"tags"`
}

var catalog = []POCExample{
	{
		ID:           "hello-loadbalancer",
		Name:         "Web Load Balancer (2 Replicas + Auto-DNS)",
		Category:     "Web & Ingress",
		Description:  "Multi-replica lightweight HTTP application with round-robin load balancing via Caddy reverse proxy and internal CoreDNS service discovery.",
		Filename:     "01-hello-loadbalancer.yml",
		DefaultStack: "hello-lb",
		Services:     []string{"hello-app"},
		Icon:         "compare_arrows",
		Tags:         []string{"loadbalancer", "caddy", "coredns", "replicas", "high-availability"},
	},
	{
		ID:           "wordpress-mysql",
		Name:         "WordPress CMS + MySQL 8.0 (Persistent Volumes)",
		Category:     "Database & CMS",
		Description:  "Production-ready WordPress publishing platform backed by a dedicated MySQL 8.0 database, persistent shared storage mounts, and Caddy ingress routing.",
		Filename:     "wordpress-mysql.yml",
		DefaultStack: "wordpress-demo",
		Services:     []string{"wordpress", "db"},
		Icon:         "web",
		Tags:         []string{"wordpress", "mysql", "database", "persistent-storage", "granaries"},
	},
	{
		ID:           "public-https",
		Name:         "Public HTTPS Web App (Automated Let's Encrypt TLS)",
		Category:     "Web & Ingress",
		Description:  "Secure public-facing web service that automatically provisions and renews SSL/TLS certificates via Caddy with Zero-Trust ACME challenges.",
		Filename:     "public-https.yml",
		DefaultStack: "public-https-demo",
		Services:     []string{"web"},
		Icon:         "lock",
		Tags:         []string{"https", "tls", "lets-encrypt", "certificates", "ingress"},
	},
	{
		ID:           "sloth-slo",
		Name:         "Google SRE Sloth SLO Monitoring (Multi-Burn-Rate Alerts)",
		Category:     "SRE & Observability",
		Description:  "Production HTTP microservice equipped with Sloth Google SRE Error Budget tracking, 30-day availability windows, and Prometheus burn-rate alerting rules.",
		Filename:     "sloth-slo.yml",
		DefaultStack: "sloth-slo-demo",
		Services:     []string{"payment-api"},
		Icon:         "speed",
		Tags:         []string{"slo", "sloth", "prometheus", "burn-rate", "error-budget"},
	},
	{
		ID:           "n8n-workflow",
		Name:         "n8n Workflow Automation + PostgreSQL",
		Category:     "Automation & AI",
		Description:  "Self-hosted workflow automation suite connecting APIs, webhooks, and data pipelines, powered by an underlying PostgreSQL relational database.",
		Filename:     "n8n-workflow.yml",
		DefaultStack: "n8n-automation",
		Services:     []string{"n8n", "postgres"},
		Icon:         "account_tree",
		Tags:         []string{"n8n", "automation", "postgres", "webhooks", "ai-agents"},
	},
	{
		ID:           "jaeger-tracing",
		Name:         "Jaeger Distributed Tracing (OpenTelemetry OTLP)",
		Category:     "SRE & Observability",
		Description:  "End-to-end distributed tracing microservice producing OTLP spans and forwarding traces to the cluster Jaeger collector on port 4318.",
		Filename:     "jaeger-tracing.yml",
		DefaultStack: "jaeger-tracing-demo",
		Services:     []string{"jaeger-app"},
		Icon:         "timeline",
		Tags:         []string{"jaeger", "opentelemetry", "tracing", "spans", "sre"},
	},
	{
		ID:           "jupyter-datascience",
		Name:         "Jupyter Lab Data Science & AI Workspace",
		Category:     "AI & Data Science",
		Description:  "Interactive Jupyter Lab container environment with Python 3, scientific libraries, and persistent notebook storage in /var/contenedores.",
		Filename:     "jupyter-datascience.yml",
		DefaultStack: "jupyter-datascience",
		Services:     []string{"jupyter"},
		Icon:         "science",
		Tags:         []string{"jupyter", "python", "data-science", "ai", "notebooks"},
	},
	{
		ID:           "sre-observability",
		Name:         "SRE Observability Microservice (Prometheus + Metrics)",
		Category:     "SRE & Observability",
		Description:  "Microservice instrumented with Prometheus latency indicators, custom health endpoints, and automatic registration in the Grafana dashboard.",
		Filename:     "sre-observability.yml",
		DefaultStack: "sre-microservice",
		Services:     []string{"monitored-api"},
		Icon:         "monitor_heart",
		Tags:         []string{"monitoring", "metrics", "prometheus", "grafana", "sre"},
	},
	{
		ID:           "kubeflow-mlops",
		Name:         "Kubeflow MLOps Platform Suite (MinIO + MLflow + PyTorch + Ollama)",
		Category:     "AI & Data Science",
		Description:  "Enterprise MLOps platform without Kubernetes complexity: MinIO S3 dataset storage, MLflow model tracking, JupyterLab PyTorch, and Ollama inference gateway with Caddy ingress.",
		Filename:     "kubeflow-mlops.yml",
		DefaultStack: "kubeflow-mlops",
		Services:     []string{"minio", "mlflow", "jupyter-workspace", "inference-engine"},
		Icon:         "psychology",
		Tags:         []string{"mlops", "kubeflow", "mlflow", "minio", "s3", "jupyter", "ollama", "ai", "pytorch"},
	},
	{
		ID:           "llama-factory",
		Name:         "LLaMA-Factory Studio (LLM Fine-Tuning WebUI)",
		Category:     "AI & Data Science",
		Description:  "Production-grade fine-tuning studio for open LLMs (LLaMA 3, Mistral, Qwen) with LoRA/QLoRA, HuggingFace dataset integration, and Gradio Web UI.",
		Filename:     "llama-factory.yml",
		DefaultStack: "llama-factory",
		Services:     []string{"llama-factory"},
		Icon:         "smart_toy",
		Tags:         []string{"llm", "fine-tuning", "lora", "llama", "huggingface", "ai", "gradio"},
	},
	{
		ID:           "deepseek-vllm",
		Name:         "DeepSeek & vLLM High-Throughput Inference Engine",
		Category:     "AI & Data Science",
		Description:  "OpenAI-compatible LLM inference server running DeepSeek R1 with vLLM PagedAttention, GPU hardware targeting, and Open-WebUI chat frontend.",
		Filename:     "deepseek-vllm.yml",
		DefaultStack: "deepseek-vllm",
		Services:     []string{"vllm-engine", "chat-ui"},
		Icon:         "neurology",
		Tags:         []string{"deepseek", "vllm", "ai", "llm", "gpu", "inference", "chat"},
	},
	{
		ID:           "pgvector-rag",
		Name:         "GenAI RAG Search & Vector Database Stack",
		Category:     "AI & Data Science",
		Description:  "Production RAG pipeline featuring PostgreSQL 16 with pgvector extension, Qdrant vector database, and Open-WebUI knowledge base search.",
		Filename:     "pgvector-rag.yml",
		DefaultStack: "pgvector-rag",
		Services:     []string{"postgres-vector", "qdrant", "rag-ui"},
		Icon:         "saved_search",
		Tags:         []string{"rag", "pgvector", "postgres", "qdrant", "vector", "ai", "embeddings"},
	},
	{
		ID:           "kafka-clickhouse",
		Name:         "Real-Time Data Streaming & Big Data Analytics",
		Category:     "Automation & AI",
		Description:  "Event-driven data pipeline combining Apache Kafka (KRaft mode - no ZooKeeper), ClickHouse columnar OLAP database, and Kafka-UI web console.",
		Filename:     "kafka-clickhouse.yml",
		DefaultStack: "kafka-clickhouse",
		Services:     []string{"kafka", "clickhouse", "kafka-ui"},
		Icon:         "insights",
		Tags:         []string{"kafka", "clickhouse", "streaming", "kraft", "analytics", "bigdata"},
	},
	{
		ID:           "gitea-woodpecker",
		Name:         "Private GitOps Forge & Container CI/CD Suite",
		Category:     "Automation & AI",
		Description:  "Lightweight self-hosted DevOps stack: Gitea source control + Woodpecker CI server and distributed worker runners placed on Centurion workers.",
		Filename:     "gitea-woodpecker.yml",
		DefaultStack: "gitea-woodpecker",
		Services:     []string{"gitea", "woodpecker-server", "woodpecker-agent"},
		Icon:         "precision_manufacturing",
		Tags:         []string{"gitea", "git", "woodpecker", "ci-cd", "devops", "gitops"},
	},
	{
		ID:           "valkey-sentinel",
		Name:         "High-Availability In-Memory Cache & Sentinel Cluster",
		Category:     "Database & CMS",
		Description:  "Fault-tolerant distributed caching stack using Valkey 7.2 (Linux Foundation Redis) with master-replica replication and quorum Sentinel failover.",
		Filename:     "valkey-sentinel.yml",
		DefaultStack: "valkey-sentinel",
		Services:     []string{"valkey-master", "valkey-replica", "valkey-sentinel"},
		Icon:         "flash_on",
		Tags:         []string{"valkey", "redis", "cache", "sentinel", "high-availability", "failover"},
	},
	{
		ID:           "keycloak-sso",
		Name:         "Enterprise Identity & Single Sign-On (SSO) Suite",
		Category:     "Database & CMS",
		Description:  "Enterprise IAM with Keycloak 24 and PostgreSQL, providing OAuth2/OIDC federation and direct integration with Gubernator LDAP/AD security.",
		Filename:     "keycloak-sso.yml",
		DefaultStack: "keycloak-sso",
		Services:     []string{"keycloak-db", "keycloak"},
		Icon:         "vpn_key",
		Tags:         []string{"keycloak", "sso", "identity", "oauth2", "oidc", "security", "ldap"},
	},
}

// GetAllPOCExamples returns all built-in POC examples with their compose definitions populated.
func GetAllPOCExamples() []POCExample {
	result := make([]POCExample, len(catalog))
	for i, ex := range catalog {
		content, err := embeddedExamples.ReadFile("data/" + ex.Filename)
		if err == nil {
			ex.ComposeRaw = string(content)
		}
		result[i] = ex
	}
	return result
}

// GetPOCExample returns a specific POC example by its unique ID.
func GetPOCExample(id string) (*POCExample, error) {
	for _, ex := range GetAllPOCExamples() {
		if ex.ID == id {
			return &ex, nil
		}
	}
	return nil, fmt.Errorf("example '%s' not found", id)
}

// DefaultServerExamplesDir returns the standard directory on the Manager where examples are exported.
func DefaultServerExamplesDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "/var/lib/gbnt/examples"
	}
	return filepath.Join(home, ".gbnt", "examples")
}

// DefaultServerStacksDir returns the standard directory on the Manager where users drop Compose stacks.
func DefaultServerStacksDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "/var/lib/gbnt/stacks"
	}
	return filepath.Join(home, ".gbnt", "stacks")
}

// EnsureServerDirectories initializes ~/.gbnt/stacks and ~/.gbnt/examples with a helpful README.
func EnsureServerDirectories() error {
	stacksDir := DefaultServerStacksDir()
	if err := os.MkdirAll(stacksDir, 0755); err != nil {
		return err
	}

	readmePath := filepath.Join(stacksDir, "README.md")
	if _, err := os.Stat(readmePath); os.IsNotExist(err) {
		readmeContent := `# Gubernator Master Server Stacks Directory

Place your Docker Compose files (\x60.yml\x60 or \x60.yaml\x60) in this directory on the Gubernator Master server:

  Path: ` + stacksDir + `

Gubernator automatically discovers files in this directory. You can deploy them:
1. Via Web UI: In "New Stack" or "Compose Studio", click "Load from Master Server" to browse and deploy.
2. Via CLI: Run \x60gbnt stack deploy --from-server ` + stacksDir + `/my-stack.yml\x60
3. Via REST API: POST /api/stacks/server-deploy with \x60{"path": "` + stacksDir + `/my-stack.yml"}\x60
`
		_ = os.WriteFile(readmePath, []byte(readmeContent), 0644)
	}

	return ExportExamplesToDisk(DefaultServerExamplesDir())
}

// ExportExamplesToDisk writes all embedded POC examples to the designated directory on the Master host.
func ExportExamplesToDisk(destDir string) error {
	if err := os.MkdirAll(destDir, 0755); err != nil {
		return fmt.Errorf("failed to create examples dir: %w", err)
	}

	for _, ex := range GetAllPOCExamples() {
		targetFile := filepath.Join(destDir, ex.Filename)
		if err := os.WriteFile(targetFile, []byte(ex.ComposeRaw), 0644); err != nil {
			slog.Warn("failed to export example file", "file", targetFile, "err", err)
		}
	}

	// Write an index README.md explaining each example
	indexMd := "# Gubernator Built-in POC Examples Library\n\n"
	indexMd += "This directory contains production-ready POC templates bundled with Gubernator:\n\n"
	indexMd += "| ID | Name | Category | File | Description |\n"
	indexMd += "| :--- | :--- | :--- | :--- | :--- |\n"
	for _, ex := range GetAllPOCExamples() {
		indexMd += fmt.Sprintf("| `%s` | %s | %s | `%s` | %s |\n", ex.ID, ex.Name, ex.Category, ex.Filename, ex.Description)
	}
	indexMd += "\n## Quick Deployment via CLI:\n```bash\n# Deploy a specific POC example:\ngbnt examples deploy wordpress-mysql\n\n# Deploy all POC examples:\ngbnt examples deploy all\n```\n"

	_ = os.WriteFile(filepath.Join(destDir, "README.md"), []byte(indexMd), 0644)
	return nil
}

// DeployPOCExample deploys a single POC example by ID to the cluster.
func DeployPOCExample(id string, targetNode string) (*db.Stack, error) {
	ex, err := GetPOCExample(id)
	if err != nil {
		return nil, err
	}

	stackName := ex.DefaultStack
	if stackName == "" {
		stackName = ex.ID
	}

	if DeployStackFn == nil {
		return nil, fmt.Errorf("stack deployment engine not initialized")
	}

	return DeployStackFn(stackName, ex.ComposeRaw, targetNode)
}

// DeployAllPOCExamples deploys all available POC examples into the cluster.
func DeployAllPOCExamples(targetNode string) ([]*db.Stack, []error) {
	var deployed []*db.Stack
	var errs []error

	for _, ex := range GetAllPOCExamples() {
		stack, err := DeployPOCExample(ex.ID, targetNode)
		if err != nil {
			errs = append(errs, fmt.Errorf("example '%s': %w", ex.ID, err))
		} else {
			deployed = append(deployed, stack)
		}
	}

	return deployed, errs
}
