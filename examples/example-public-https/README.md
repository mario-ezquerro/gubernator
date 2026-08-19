# 🌐 Example: Automatic Public HTTPS with Let's Encrypt (`demo.fiware.app`)

This example demonstrates how to deploy a containerized service with a **real public domain** (e.g. `demo.fiware.app`). Gubernator and Caddy automatically handle:
1. **ACME Challenge** with Let's Encrypt / ZeroSSL.
2. **Instant X.509 Certificate Issuance** & HTTPS activation on port `443`.
3. **HTTP (port 80) ➔ HTTPS (port 443) Automatic Redirection**.
4. **Auto-Renewal** 30 days before certificate expiration.

---

## 📋 Prerequisites

1. **DNS `A` Record**: Create an `A` record in your DNS provider (Cloudflare, GoDaddy, Route53, etc.) pointing `demo.fiware.app` to your server's public IP:
   ```text
   demo.fiware.app  IN  A  <YOUR_PUBLIC_SERVER_IP>
   ```
2. **Open Firewall Ports**: Ensure ports `80` (HTTP) and `443` (HTTPS) are open in your cloud provider's firewall / security groups.

---

## 🚀 Deployment

### Via CLI
```bash
gbnt stack deploy -c docker-compose.yml public-https-demo
```

### Via Web Dashboard
1. Open the Gubernator Web UI at `http://<MANAGER_IP>:4001/`.
2. Go to **Stacks ➔ Deploy Stack**.
3. Paste the contents of `docker-compose.yml` and click **Deploy**.

---

## 🔍 Verification & Certificate Inspection

1. Open your browser and navigate to:
   ```text
   https://demo.fiware.app
   ```
   You will see a valid green padlock with a globally trusted SSL certificate issued by **Let's Encrypt** or **ZeroSSL**.

2. In the Gubernator Dashboard, open **Caddy Ingress ➔ TLS Certs**:
   - Inspect the X.509 certificate properties, issuer, days remaining, and cryptographic fingerprint.
   - You can also trigger forced renewals or download the certificate `.crt` file.
