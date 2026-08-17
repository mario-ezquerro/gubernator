---
title: Cómo dotamos a Gubernator de Autenticación Empresarial con Active Directory, LDAP y RBAC en Go & Flutter usando Google Antigravity
published: false
description: Arquitectura e implementación de autenticación multi-directorio Active Directory (LDAPS), tokens JWT y control de acceso basado en roles (RBAC) en el orquestador Gubernator con pair-programming de Google Antigravity.
tags: go, docker, devops, flutter, ai
cover_image: https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/security_ad.png
---

# 🏛️ Cómo dotamos a Gubernator de Autenticación Empresarial con Active Directory, LDAP y RBAC usando Google Antigravity

Cuando construyes un orquestador de contenedores como **[Gubernator (gbnt)](https://github.com/mario-ezquerro/gubernator)** —cuyo objetivo es ofrecer el punto óptimo entre la **simplicidad de Docker Swarm** y la **potencia de Nomad** con temática del Imperio Romano—, tarde o temprano surge un hito ineludible para dar el salto a entornos corporativos reales: **la seguridad empresarial y el control de acceso**.

Tener un usuario `admin` por defecto está bien para un laboratorio local. Pero en una infraestructura de producción empresarial con cientos de ingenieros, necesitas:
1. **Single Sign-On (SSO) con Microsoft Active Directory y OpenLDAP**.
2. **Control de Acceso Basado en Roles (RBAC)** para segregar quién puede desplegar, quién puede reiniciar tareas y quién tiene acceso solo de lectura/auditoría.
3. **Mapeo dinámico de Grupos de Seguridad** de la empresa hacia roles del orquestador.
4. **Acceso de Emergencia (Break-glass Local Admin)** por si los controladores de dominio están caídos.

En este artículo explicamos la arquitectura completa de esta feature introducida en **Gubernator v2.20.0** y cómo utilizamos **Google Antigravity (AGY)** para acelerar el diseño, la implementación Full-Stack (Go + Flutter Web) y la validación en un clúster real de 3 nodos.

---

## 🏗️ La Arquitectura de Seguridad

Diseñamos una arquitectura asimétrica desacoplada entre el motor de identidades, la API REST y el frontend web:

```
 ┌────────────────────────────────────────────────────────┐
 │                   GUBERNATOR WEB UI                    │
 │   - Pantalla de Login con Selector de Directorio / AD  │
 │   - Header con Badge de Rol: 👑 Admin | ⚡ Ops | 👁️ View│
 └──────────────────────────┬─────────────────────────────┘
                            │ (REST /api/auth/login)
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │             GUBERNATOR CORE AUTH ENGINE (Go)           │
 │  - Local Emergency Admin (admin / admin fallback)      │
 │  - Multi-Server Active Directory / OpenLDAP Dialers    │
 │  - Negociación LDAPS (Puerto 636) y StartTLS (389)     │
 │  - Resolución Dinámica: Group DN -> Rol RBAC           │
 │  - Emisión y Firma de Tokens JWT (HMAC-SHA256)         │
 └─────────────┬────────────────────────────┬─────────────┘
               │                            │
               ▼                            ▼
 ┌───────────────────────────┐ ┌──────────────────────────┐
 │  Primary Active Directory │ │ Secondary LDAP Server    │
 │   dc1.corporate.local     │ │   dc2.dr-site.local      │
 └───────────────────────────┘ └──────────────────────────┘
```

### 👥 Matriz de Roles (RBAC)

Definimos tres niveles operativos bien diferenciados:

| Capacidad Operativa | 👑 `admin` | ⚡ `operator` | 👁️ `readonly` |
| :--- | :---: | :---: | :---: |
| **Overview, Métricas y Telemetría** | ✅ Total | ✅ Total | ✅ Total |
| **Desplegar Stacks (`docker-compose.yml`)** | ✅ Total | ✅ Total | ❌ Bloqueado |
| **Re-desplegar y Duplicar Stacks** | ✅ Total | ✅ Total | ❌ Bloqueado |
| **Eliminar Stacks** | ✅ Total | ❌ Bloqueado | ❌ Bloqueado |
| **Ciclo de Tareas (Start / Stop / Restart)** | ✅ Total | ✅ Total | ❌ Bloqueado |
| **Acceso a Shell / Terminal de Contenedores** | ✅ Total | ✅ Total | ❌ Bloqueado |
| **Gestión de Nodos (Drain, Activate, Leave)** | ✅ Total | ❌ Bloqueado | ❌ Bloqueado |
| **Certificados TLS y Rutas Caddy** | ✅ Total | ❌ Bloqueado | ❌ Bloqueado |
| **Gestión de Servidores Active Directory / LDAP** | ✅ Total | ❌ Bloqueado | ❌ Bloqueado |
| **Dashboards de Grafana, Jaeger y Weave Scope** | ✅ Total | ✅ Total | ✅ Total |

---

## 💻 El Motor en Go (`internal/auth/`)

Para la autenticación LDAP/Active Directory utilizamos `github.com/go-ldap/ldap/v3` y para la gestión de sesiones `github.com/golang-jwt/jwt/v5`.

### 1. Búsqueda y Validación de Credenciales
El proceso sigue un patrón seguro en dos fases:
1. Conexión y **Bind de Servicio** con una cuenta técnica (`BindDN` / `BindPassword`).
2. Búsqueda del usuario mediante filtro configurable (por defecto `(&(objectClass=user)(sAMAccountName=%s))`).
3. Conexión secundaria y **Direct User Bind** con las credenciales introducidas por el operador para validar su contraseña contra el controlador de dominio.

```go
func AuthenticateLDAP(cfg db.LDAPConfig, username, password string) (*AuthResult, error) {
    conn, err := ConnectLDAP(cfg)
    if err != nil {
        return nil, err
    }
    defer conn.Close()

    // 1. Bind de cuenta de servicio
    if cfg.BindDN != "" && cfg.BindPassword != "" {
        if err := conn.Bind(cfg.BindDN, cfg.BindPassword); err != nil {
            return nil, fmt.Errorf("service account bind failed: %w", err)
        }
    }

    // 2. Búsqueda del usuario
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

    // 3. Autenticación con las credenciales del usuario
    userConn, err := ConnectLDAP(cfg)
    if err != nil {
        return nil, err
    }
    defer userConn.Close()

    if err := userConn.Bind(userEntry.DN, password); err != nil {
        return nil, errors.New("invalid credentials")
    }

    // 4. Mapeo de grupos a rol RBAC
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

### 2. Mapeo Dinámico de Grupos a Roles
Gubernator compara las membresías del usuario contra los DNs configurados para cada rol:

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

## 🎨 La Experiencia en Flutter Web

El Web Dashboard de Gubernator está construido en **Flutter Web** con **Material Design 3** y compilado directamente dentro del binario Go (`go:embed`).

### 1. Pantalla de Login con Selector de Directorio
Permite a los usuarios elegir si se autentican contra el **Active Directory Primario**, un **Directorio Secundario** o el **Administrador Local**:

![Login Screen](https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/login_screen.png)

### 2. Suite de Administración de Active Directory & Diagnóstico
En la nueva pestaña **Seguridad & AD**, los administradores pueden añadir servidores, configurar certificados LDAPS y ejecutar la herramienta de diagnóstico **"Test Connection"** en tiempo real:

![Security & AD Management](https://raw.githubusercontent.com/mario-ezquerro/gubernator/main/docs/images/security_ad.png)

### 3. Badge de Rol en Tiempo Real
En la barra superior, la interfaz muestra el avatar, nombre de usuario y el badge del rol asignado (`👑 ADMIN`, `⚡ OPERATOR`, `👁️ READ-ONLY`), adaptando dinámicamente los botones y acciones permitidas en cada pantalla.

---

## 🚀 El Rol de Google Antigravity en el Desarrollo

Para construir esta funcionalidad de principio a fin, utilizamos **Google Antigravity (AGY)** como agente de pair-programming autónomo. La experiencia fue clave en varios aspectos:

1. **Arquitectura y Planificación Previa**:
   Antigravity elaboró un plan de implementación detallado (`implementation_plan.md`) definiendo la matriz de permisos, el modelo de base de datos GORM (`LDAPConfig`), las rutas API y los cambios en la UI antes de escribir código.

2. **Desarrollo Full-Stack Sincronizado**:
   En una sola sesión iterativa, Antigravity:
   - Creó el paquete Go `internal/auth/` con soporte LDAP, JWT y middlewares Gin.
   - Actualizó los modelos GORM y la migración automática de SQLite.
   - Creó las pantallas de Flutter (`login_screen.dart`, `security_page.dart`) y actualizó el `ApiService`.
   - Modificó las vistas existentes (`legions_page.dart`, `tasks_page.dart`, `centurions_page.dart`) para respetar los permisos del usuario.

3. **Validación en un Clúster Real**:
   Mediante comandos automatizados en un clúster multipass de 3 nodos (`gbnt-manager`, `gbnt-worker1`, `gbnt-worker2`), Antigravity:
   - Desplegó y reinició los binarios ARM64 en caliente.
   - Probó los endpoints REST mediante `curl` (login válido, login inválido, test de conexión LDAP, borrado de configuración).
   - Verificó que los tests unitarios pasaran al 100% en Go (`go test ./internal/auth/...`).

4. **Documentación y Versionado Automático**:
   - Generación de capturas de pantalla de alta fidelidad.
   - Creación de la documentación en [`docs/auth-rbac.md`](https://mario-ezquerro.github.io/gubernator/auth-rbac/) y compilación estricta de **MkDocs**.
   - Bump de versión a `v2.20.0`, creación del tag Git y sincronización con GitHub Pages.

---

## 🏁 Conclusión y Enlaces

Dotar a Gubernator de autenticación Active Directory y RBAC permite llevar un orquestador ligero a organizaciones corporativas que necesitan cumplimiento de seguridad sin la complejidad abrumadora de Kubernetes.

Puedes probar Gubernator o desplegarlo en tu propia infraestructura:

* 📦 **Repositorio en GitHub:** [github.com/mario-ezquerro/gubernator](https://github.com/mario-ezquerro/gubernator)
* 📖 **Documentación Oficial:** [mario-ezquerro.github.io/gubernator](https://mario-ezquerro.github.io/gubernator/)
* 🛡️ **Guía de Active Directory & RBAC:** [docs/auth-rbac.md](https://mario-ezquerro.github.io/gubernator/auth-rbac/)

¿Qué opinas sobre este enfoque híbrido para orquestación de contenedores? ¡Déjanos tus comentarios y sugerencias en GitHub! 🏛️
