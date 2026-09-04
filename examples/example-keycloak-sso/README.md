# Enterprise Identity & Single Sign-On (SSO) Suite

Enterprise-grade user federation, OAuth2/OIDC provider, and Single Sign-On powered by **Keycloak** and PostgreSQL.

## 🏛️ Components
1. **`keycloak-db`**: PostgreSQL database storing user realms, credentials, sessions, and security policies.
2. **`keycloak`**: OpenID Connect and SAML 2.0 authentication server with granular user and group management.

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: Web console and authentication redirect endpoints at `http://auth.gbnt.local`.
* **Gubernator Enterprise Auth Bridge**: Seamless integration with Gubernator's Active Directory and OpenLDAP security layer.
* **The Granaries Persistence**: Relational identities safely stored in `/var/contenedores/keycloak/postgres`.

## 💻 Quick Deploy
```bash
gbnt examples deploy keycloak-sso
```
