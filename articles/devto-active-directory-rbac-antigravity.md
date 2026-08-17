---
title: Building Enterprise Active Directory, LDAP & Dynamic RBAC in Go & Flutter with Google Antigravity
published: false
description: A deep dive into implementing multi-server Active Directory SSO (LDAPS), JWT authentication, and 3-tier RBAC for Gubernator using Google Antigravity as an AI pair programmer.
tags: go, docker, devops, flutter, ai
cover_image: https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/security_ad.png
---

# 🏛️ Building Enterprise Active Directory, LDAP & Dynamic RBAC in Go & Flutter with Google Antigravity

When building a lightweight container orchestrator like **[Gubernator (gbnt)](https://github.com/mario-ezquerro/gubernator)** — designed to strike the perfect balance between the **simplicity of Docker Swarm** and the **flexibility of Nomad** under a Roman Empire theme — a critical milestone inevitably emerges: **Enterprise Security and Access Control**.

While a default `admin` credential works well for local dev environments, moving into enterprise production with multi-disciplinary engineering teams demands:
1. **Corporate Single Sign-On (SSO)** with Microsoft Active Directory and OpenLDAP.
2. **Role-Based Access Control (RBAC)** to clearly segregate who can deploy stacks, restart containers, or audit telemetries in read-only mode.
3. **Dynamic Group Mapping** from corporate security groups (`memberOf`) to orchestrator roles.
4. **Emergency Break-Glass Access** (Local Administrator) in case network directory controllers are unreachable.

In this article, we explore the complete architecture of the enterprise security engine introduced in **Gubernator v2.20.0**, and how we leveraged **Google Antigravity (AGY)** as an autonomous AI pair programmer to design, implement, test, and verify this Full-Stack feature (Go + Flutter Web) across a live 3-node cluster.

---

## 🏗️ The Security Architecture

We designed a decoupled, asymmetric architecture connecting identity providers, REST API middleware, and the Flutter Web UI:

```
 ┌────────────────────────────────────────────────────────┐
 │                   GUBERNATOR WEB UI                    │
 │   - Modern Login Screen with Domain / AD Selector      │
 │   - Header Role Badge: 👑 Admin | ⚡ Ops | 👁️ Read-Only│
 └──────────────────────────┬─────────────────────────────┘
                            │ (REST /api/auth/login)
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │             GUBERNATOR CORE AUTH ENGINE (Go)           │
 │  - Local Emergency Admin (admin / admin fallback)      │
 │  - Multi-Server Active Directory / OpenLDAP Dialers    │
 │  - LDAPS (Port 636) & StartTLS (Port 389) Handshake    │
 │  - Dynamic Group DN -> RBAC Role Resolution            │
 │  - Cryptographic HMAC-SHA256 JWT Token Signing         │
 └─────────────┬────────────────────────────┬─────────────┘
               │                            │
               ▼                            ▼
 ┌───────────────────────────┐ ┌──────────────────────────┐
 │  Primary Active Directory │ │ Secondary LDAP Server    │
 │   dc1.corporate.local     │ │   dc2.dr-site.local      │
 └───────────────────────────┘ └──────────────────────────┘
```

### 👥 Role-Based Access Control (RBAC) Matrix

We established three distinct operational tiers:

| Operational Capability | 👑 `admin` | ⚡ `operator` | 👁️ `readonly` |
| :--- | :---: | :---: | :---: |
| **Overview, Metrics & SRE Telemetry** | ✅ Full | ✅ Full | ✅ Full |
| **Deploy Stacks (`docker-compose.yml`)** | ✅ Full | ✅ Full | ❌ Restricted |
| **Redeploy & Duplicate Stacks** | ✅ Full | ✅ Full | ❌ Restricted |
| **Delete Stacks** | ✅ Full | ❌ Restricted | ❌ Restricted |
| **Task Lifecycle (Start / Stop / Restart)** | ✅ Full | ✅ Full | ❌ Restricted |
| **Container & Node Terminal Shell** | ✅ Full | ✅ Full | ❌ Restricted |
| **Node Fleet Management (Drain / Activate / Leave)** | ✅ Full | ❌ Restricted | ❌ Restricted |
| **Caddy TLS Certificates & Ingress Routes** | ✅ Full | ❌ Restricted | ❌ Restricted |
| **Active Directory & LDAP Directory Settings** | ✅ Full | ❌ Restricted | ❌ Restricted |
| **Grafana, Jaeger & Weave Scope Dashboards** | ✅ Full | ✅ Full | ✅ Full |

---

## 💻 The Go Backend Engine (`internal/auth/`)

For LDAP/Active Directory interactions, we used `github.com/go-ldap/ldap/v3`, and for session management `github.com/golang-jwt/jwt/v5`.

### 1. Two-Phase Bind & Credential Verification
Authentication follows a secure two-phase pattern:
1. Connect and perform a **Service Account Bind** (`BindDN` / `BindPassword`) to query the directory.
2. Search for the user object using a configurable LDAP filter (defaulting to `(&(objectClass=user)(sAMAccountName=%s))`).
3. Open a secondary connection and perform a **Direct User Bind** with the user-submitted password against the domain controller.

```go
func AuthenticateLDAP(cfg db.LDAPConfig, username, password string) (*AuthResult, error) {
    conn, err := ConnectLDAP(cfg)
    if err != nil {
        return nil, err
    }
    defer conn.Close()

    // 1. Initial service account bind
    if cfg.BindDN != "" && cfg.BindPassword != "" {
        if err := conn.Bind(cfg.BindDN, cfg.BindPassword); err != nil {
            return nil, fmt.Errorf("service account bind failed: %w", err)
        }
    }

    // 2. Search for the user
    filter := fmt.Sprintf(cfg.UserFilter, ldap.EscapeFilter(username))
    searchReq := ldap.NewSearchRequest(
        cfg.BaseDN,
        ldap.ScopeWholeSubtree, ldap.NeverDerefAliases, 0, 0, false,
        filter,
        []string{"dn", "displayName", "mail", "memberOf"},
        nil,
    )
    sr, err := conn.Search(searchReq)
    if err != nil || len(sr.Entries) == 0 {
        return nil, errors.New("user not found in directory")
    }

    userEntry := sr.Entries[0]

    // 3. Direct user bind to verify password
    userConn, err := ConnectLDAP(cfg)
    if err != nil {
        return nil, err
    }
    defer userConn.Close()

    if err := userConn.Bind(userEntry.DN, password); err != nil {
        return nil, errors.New("invalid credentials")
    }

    // 4. Map groups to RBAC role
    groups := userEntry.GetAttributeValues("memberOf")
    role := ResolveRole(cfg, groups)

    return &AuthResult{
        UserDN:      userEntry.DN,
        Username:    username,
        DisplayName: userEntry.GetAttributeValue("displayName"),
        Email:       userEntry.GetAttributeValue("mail"),
        Groups:      groups,
        Role:        role,
    }, nil
}
```

### 2. Dynamic Group-to-Role Mapping
Gubernator inspects the user's `memberOf` group list and matches them against the configured group DNs:

```go
func ResolveRole(cfg db.LDAPConfig, userGroups []string) Role {
    matchesGroup := func(targetGroup string) bool {
        if targetGroup == "" { return false }
        target := strings.ToLower(strings.TrimSpace(targetGroup))
        for _, g := range userGroups {
            if strings.ToLower(strings.TrimSpace(g)) == target {
                return true
            }
        }
        return false
    }

    if matchesGroup(cfg.AdminGroupDN) { return RoleAdmin }
    if matchesGroup(cfg.OperatorGroupDN) { return RoleOperator }
    if matchesGroup(cfg.ReadOnlyGroupDN) { return RoleReadOnly }

    return NormalizeRole(cfg.DefaultRole)
}
```

---

## 🎨 The Flutter Web UI Experience

Gubernator's Web Dashboard is built with **Flutter Web** and **Material Design 3**, compiled and embedded directly into the Go binary (`go:embed`).

### 1. Modern Login Screen with Domain Selector
Operators can select their target authentication provider (`Corporate Active Directory`, `DR Site LDAP`, or `Local Administrator`):

![Login Screen](https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/login_screen.png)

### 2. Active Directory Management & Diagnostics
In the new **Seguridad & AD** tab, cluster administrators can configure directory servers, TLS certificates, and run a live **"Test Connection"** diagnostic tool:

![Security & AD Management](https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/security_ad.png)

### 3. Real-Time Role Badges & Contextual Guards
The dashboard header displays the active user and their assigned role (`👑 ADMIN`, `⚡ OPERATOR`, `👁️ READ-ONLY`). Mutating actions (e.g., Delete Stack, Drain Node, Shell) are automatically disabled for read-only audit accounts.

---

## 🚀 How Google Antigravity Accelerated Development

We utilized **Google Antigravity (AGY)** as an autonomous AI pair programmer to build this feature end-to-end. AGY accelerated the development cycle through several key workflows:

1. **Architectural Planning**:
   Before writing code, Antigravity produced a comprehensive implementation plan (`implementation_plan.md`) outlining the GORM schema changes (`LDAPConfig`), RBAC authorization matrix, and API routes.

2. **Synchronized Full-Stack Implementation**:
   In a single coordinated session, Antigravity:
   - Built the Go `internal/auth/` engine with LDAP dialers, JWT session handlers, and Gin middlewares.
   - Applied SQLite database auto-migrations.
   - Implemented the Flutter Web UI (`login_screen.dart`, `security_page.dart`, and state models).
   - Updated existing views (`legions_page.dart`, `tasks_page.dart`, `centurions_page.dart`) with RBAC permission guards.

3. **Live Cluster Testing & Verification**:
   Using automated commands across a 3-node multipass cluster (`gbnt-manager`, `gbnt-worker1`, `gbnt-worker2`), Antigravity:
   - Deployed and hot-restarted the ARM64 binaries.
   - Tested REST endpoints via `curl` (valid login, invalid login, LDAP connection tests, configuration lifecycle).
   - Executed Go unit tests (`go test ./internal/auth/...`) with 100% pass rates.

4. **Automated Documentation & Release**:
   - Generated high-fidelity visual UI showcases.
   - Authored complete documentation in [`docs/auth-rbac.md`](https://mario-ezquerro.github.io/gubernator/auth-rbac/) and validated MkDocs builds in strict mode.
   - Bumped the version to `v2.20.0`, created git release tags, and triggered GitHub Pages publishing.

---

## 🏁 Conclusion & Open Source

Adding Active Directory SSO and RBAC allows teams to deploy Gubernator in enterprise production environments that require enterprise security compliance without the operational overhead of Kubernetes.

Check out Gubernator and try it out:

* 📦 **GitHub Repository:** [github.com/mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)
* 📖 **Official Documentation:** [mario-ezquerro.github.io/gubernator](https://mario-ezquerro.github.io/gubernator/)
* 🛡️ **Active Directory & RBAC Guide:** [docs/auth-rbac.md](https://mario-ezquerro.github.io/gubernator/auth-rbac/)

What do you think about this hybrid approach to container orchestration? Let us know your thoughts and suggestions in the comments! 🏛️
