# Enterprise Identity & Single Sign-On (SSO) Suite

Enterprise-grade user federation, OAuth2/OIDC provider, and Single Sign-On powered by **Keycloak** and PostgreSQL.

## 🏛️ Components
1. **`keycloak-db`**: Dedicated PostgreSQL 16 database storing user realms, credentials, sessions, and security policies.
2. **`keycloak`**: OpenID Connect and SAML 2.0 authentication server (Quarkus runtime) with granular user and group management.

## 🔑 Default Credentials
* **Admin Console URL**: `http://auth.gbnt.local` (or `https://auth.gbnt.local`)
* **Username**: `admin`
* **Password**: `admin`

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: Web console and authentication redirect endpoints at `http://auth.gbnt.local` with automatic TLS internal certificates and HTTP-to-HTTPS upgrade.
* **CoreDNS Inter-Service Resolution**: Seamless inter-container database connectivity via cluster-wide DNS (`keycloak-db.keycloak-sso.gbnt.local` and bare `keycloak-db`).
* **Gubernator Enterprise Auth Bridge**: Seamless integration with Gubernator's Active Directory and OpenLDAP security layer.
* **The Granaries Persistence**: Relational identities safely stored in `/var/contenedores/keycloak/postgres` with automated directory permission handling.

## 💻 Quick Deploy
```bash
gbnt examples deploy keycloak-sso
```

To view running containers and live metrics:
```bash
gbnt task ls
```
