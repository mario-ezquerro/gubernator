#!/usr/bin/env bash
# ==============================================================================
# Gubernator — Dual-NIC 2-Node Clean Cluster Provisioning Script (Multipass)
# ==============================================================================
# Provisions 2 Multipass Ubuntu 24.04 nodes:
# - gbnt-manager (Manager + API + Web Dashboard + SRE Monitor stack)
# - gbnt-worker1 (Centurion Worker 1)
# Installs: Docker CE, GlusterFS, passwordless SSH, Gubernator (systemd),
#           Weave Scope topology (app on manager, probe on worker).
# Requires: bin/gbnt-linux-arm64 (GOOS=linux GOARCH=arm64 go build ./cmd/gbnt)
# ==============================================================================

set -euo pipefail

NODES=(gbnt-manager gbnt-worker1)
WORKERS=(gbnt-worker1)
API_TOKEN="${GBNT_API_TOKEN:-my-gubernator-api-token}"
ADMIN_PASSWORD="${GBNT_ADMIN_PASSWORD:-admin}"
BRIDGE_IF="${GBNT_BRIDGE_IF:-en0}"
SCOPE_IMAGE="cloudresources/scope:latest"
SCOPE_PORT=4040

if [ ! -f bin/gbnt-linux-arm64 ]; then
  echo "❌ bin/gbnt-linux-arm64 not found. Build it first:"
  echo "   GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags \"-X main.version=\$(cat VERSION)\" -o bin/gbnt-linux-arm64 ./cmd/gbnt"
  exit 1
fi

if [ "${GBNT_REUSE_VMS:-0}" != "1" ]; then
  echo "🛑 1. Deleting and purging existing Gubernator instances..."
  multipass delete -p gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3 2>/dev/null || true

  echo "🚀 2. Launching 2 clean Multipass Ubuntu 24.04 nodes with Dual Network Interfaces..."
  multipass launch 24.04 --name gbnt-manager --cpus 4 --memory 6G --disk 30G --network name="$BRIDGE_IF",mode=manual
  multipass launch 24.04 --name gbnt-worker1 --cpus 2 --memory 3G --disk 20G --network name="$BRIDGE_IF",mode=manual
else
  echo "♻️  Reusing existing gbnt-manager / gbnt-worker1 instances (GBNT_REUSE_VMS=1)"
fi

echo "⏳ Waiting for SSH readiness on all nodes..."
for NODE in "${NODES[@]}"; do
  for i in $(seq 1 30); do
    if multipass exec "$NODE" -- true 2>/dev/null; then break; fi
    sleep 3
  done
done

echo "🌐 3. Configuring dedicated storage network (10.10.100.0/24) on enp0s2..."
storage_ip() {
  case "$1" in
    gbnt-manager) echo 10.10.100.27 ;;
    gbnt-worker1) echo 10.10.100.25 ;;
  esac
}
for NODE in "${NODES[@]}"; do
  cat > "/tmp/netplan-${NODE}.yaml" << EOF
network:
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - $(storage_ip "$NODE")/24
      dhcp4: false
EOF
  multipass transfer "/tmp/netplan-${NODE}.yaml" "$NODE":/tmp/50-storage.yaml
  multipass exec "$NODE" -- sudo mv /tmp/50-storage.yaml /etc/netplan/50-storage.yaml
  multipass exec "$NODE" -- sudo chmod 600 /etc/netplan/50-storage.yaml
  multipass exec "$NODE" -- sudo netplan apply
done

echo "🔍 Verifying storage network connectivity..."
multipass exec gbnt-manager -- ping -c 2 10.10.100.25 || echo "⚠️  Storage network ping failed (continuing)"

echo "🐳 4. Installing Docker CE, GlusterFS, and tools on both nodes..."
for NODE in "${NODES[@]}"; do
  echo "==> Configuring packages on $NODE..."
  multipass exec "$NODE" -- sudo apt-get update -y
  multipass exec "$NODE" -- sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg jq glusterfs-server glusterfs-client attr
  multipass exec "$NODE" -- sudo systemctl enable --now glusterd
  multipass exec "$NODE" -- bash -c "curl -fsSL https://get.docker.com | sudo sh"
  multipass exec "$NODE" -- sudo usermod -aG docker ubuntu
  multipass exec "$NODE" -- sudo mkdir -p /data/glusterfs/brick1 /var/contenedores
  multipass exec "$NODE" -- sudo chmod 0777 /data/glusterfs/brick1 /var/contenedores
  multipass exec "$NODE" -- sudo docker pull alpine:latest || true
done

echo "🔑 5. Setting up unified SSH keys across cluster..."
multipass exec gbnt-manager -- bash -c "
  rm -f /home/ubuntu/.ssh/id_ed25519*
  ssh-keygen -t ed25519 -N '' -f /home/ubuntu/.ssh/id_ed25519
  sudo mkdir -p /data/ssh
  sudo cp /home/ubuntu/.ssh/id_ed25519* /data/ssh/
  sudo chown -R ubuntu:ubuntu /data/ssh
  sudo chmod 600 /data/ssh/id_ed25519
"
MGR_PUB_KEY=$(multipass exec gbnt-manager -- cat /home/ubuntu/.ssh/id_ed25519.pub)

for NODE in "${NODES[@]}"; do
  multipass exec "$NODE" -- bash -c "echo '$MGR_PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys"
  multipass exec "$NODE" -- bash -c "
    mkdir -p /home/ubuntu/.ssh
    echo 'StrictHostKeyChecking no' >> /home/ubuntu/.ssh/config
    chmod 600 /home/ubuntu/.ssh/config
  "
done

echo "🔍 Testing passwordless SSH from manager to all nodes..."
for NODE in "${NODES[@]}"; do
  NODE_IP=$(multipass info "$NODE" | grep -E 'IPv4' | awk '{print $2}')
  echo "Testing SSH to $NODE ($NODE_IP)..."
  multipass exec gbnt-manager -- ssh -i /data/ssh/id_ed25519 -o StrictHostKeyChecking=no "ubuntu@$NODE_IP" "hostname"
done

echo "📦 6. Deploying freshly compiled Gubernator binary..."
for NODE in "${NODES[@]}"; do
  multipass transfer bin/gbnt-linux-arm64 "$NODE":/home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo chmod +x /home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo cp /home/ubuntu/gbnt /usr/local/bin/gbnt
done

echo "👑 7. Starting Gubernator Manager service on gbnt-manager..."
MGR_PRIMARY_IP=$(multipass info gbnt-manager | grep -E 'IPv4' | awk '{print $2}')
multipass exec gbnt-manager -- sudo bash -c "cat << 'EOF' > /etc/systemd/system/gbnt-manager.service
[Unit]
Description=Gubernator Orchestrator Manager
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/ubuntu
Environment=\"GBNT_API_TOKEN=$API_TOKEN\"
Environment=\"GBNT_HOST_IP=$MGR_PRIMARY_IP\"
Environment=\"GBNT_DATA_DIR=/home/ubuntu/data\"
Environment=\"GBNT_WEB=true\"
Environment=\"GBNT_WEB_USER=admin\"
Environment=\"GBNT_WEB_PASSWORD=$ADMIN_PASSWORD\"
Environment=\"GBNT_MONITOR=true\"
ExecStart=/home/ubuntu/gbnt serve
Restart=always
RestartSec=3s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF"

multipass exec gbnt-manager -- sudo mkdir -p /home/ubuntu/data
multipass exec gbnt-manager -- sudo systemctl daemon-reload
multipass exec gbnt-manager -- sudo systemctl enable --now gbnt-manager.service

# CLI contexts (~/.gbntctl/config) for ubuntu and root
write_ctx() {
  local NODE=$1 NAME=$2 SERVER=$3
  multipass exec "$NODE" -- sudo bash -c "
mkdir -p /home/ubuntu/.gbntctl /root/.gbntctl
cat << 'EOF' > /home/ubuntu/.gbntctl/config
current-context: $NAME
contexts:
  - name: $NAME
    server: $SERVER
    token: $API_TOKEN
EOF
cp /home/ubuntu/.gbntctl/config /root/.gbntctl/config
chown -R ubuntu:ubuntu /home/ubuntu/.gbntctl
chmod 600 /home/ubuntu/.gbntctl/config /root/.gbntctl/config
"
}
write_ctx gbnt-manager local http://localhost:4000
for WORKER in "${WORKERS[@]}"; do
  write_ctx "$WORKER" cluster "http://$MGR_PRIMARY_IP:4000"
done

for NODE in "${NODES[@]}"; do
  multipass exec "$NODE" -- bash -c "echo 'export GBNT_API_TOKEN=$API_TOKEN' >> /home/ubuntu/.bashrc"
  multipass exec "$NODE" -- sudo bash -c "echo 'export GBNT_API_TOKEN=$API_TOKEN' >> /root/.bashrc"
done

echo "⏳ Waiting for Manager API on :4000..."
for i in $(seq 1 30); do
  if multipass exec gbnt-manager -- curl -fsS -o /dev/null http://localhost:4000/v1/node/ls -H "Authorization: Bearer $API_TOKEN" 2>/dev/null; then
    echo "✅ Manager API is up"; break
  fi
  sleep 2
done

echo "🔑 8. Getting cluster join token..."
JOIN_TOKEN=$(multipass exec gbnt-manager -- env GBNT_API_TOKEN="$API_TOKEN" /usr/local/bin/gbnt legion join-token 2>/dev/null | grep -oE '[a-f0-9]{32}' | head -n 1 || true)
if [ -z "$JOIN_TOKEN" ]; then
  JOIN_TOKEN="d04de109ec96411d1fd7672e04725244"
fi
echo "Join Token: $JOIN_TOKEN"

echo "💻 9. Setting up systemd service for worker node(s)..."
for WORKER in "${WORKERS[@]}"; do
  echo "Configuring $WORKER..."
  multipass exec "$WORKER" -- sudo bash -c "cat << 'EOF' > /etc/systemd/system/gbnt-worker.service
[Unit]
Description=Gubernator Worker Agent (Centurion)
Documentation=https://github.com/mario-ezquerro/gubernator
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/gbnt legion join --manager http://$MGR_PRIMARY_IP:4000 --token $JOIN_TOKEN --api-token $API_TOKEN
Restart=always
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF"
  multipass exec "$WORKER" -- sudo systemctl daemon-reload
  multipass exec "$WORKER" -- sudo systemctl enable --now gbnt-worker.service
done

echo "🧱 10. Probing GlusterFS peers (storage network 10.10.100.0/24, fallback to primary network)..."
sleep 4
WORKER1_IP=$(multipass info gbnt-worker1 | grep -E 'IPv4' | awk '{print $2}')
if multipass exec gbnt-manager -- timeout 3 bash -c '</dev/tcp/10.10.100.25/24007' 2>/dev/null; then
  multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.25 || true
else
  echo "⚠️  TCP over storage NIC blocked (Wi-Fi bridge?) — peering over primary IP $WORKER1_IP"
  multipass exec gbnt-manager -- sudo gluster peer probe "$WORKER1_IP" || true
fi
multipass exec gbnt-manager -- sudo gluster peer status || true

echo "🛰  11. Deploying Weave Scope topology (app on manager :$SCOPE_PORT, probe on workers)..."
multipass exec gbnt-manager -- sudo docker rm -f gbnt-wave-scope 2>/dev/null || true
multipass exec gbnt-manager -- sudo docker run -d --name gbnt-wave-scope --restart always \
  --network host --pid host --privileged \
  -v /var/run/docker.sock:/var/run/docker.sock -v /sys/kernel/debug:/sys/kernel/debug \
  "$SCOPE_IMAGE" --probe.docker=true --app.http.address=:$SCOPE_PORT || echo "⚠️  Scope app failed (continuing)"
for WORKER in "${WORKERS[@]}"; do
  multipass exec "$WORKER" -- sudo docker rm -f gbnt-wave-scope 2>/dev/null || true
  multipass exec "$WORKER" -- sudo docker run -d --name gbnt-wave-scope --restart always \
    --network host --pid host --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock -v /sys/kernel/debug:/sys/kernel/debug \
    "$SCOPE_IMAGE" --probe.docker=true "$MGR_PRIMARY_IP:$SCOPE_PORT" || echo "⚠️  Scope probe failed on $WORKER (continuing)"
done

echo "📊 12. Initializing SRE monitoring stack (Prometheus, Grafana, Loki, cAdvisor, Jaeger)..."
multipass exec gbnt-manager -- env GBNT_API_TOKEN="$API_TOKEN" /usr/local/bin/gbnt monitor init || true

sleep 5
echo "🏛  Cluster nodes:"
multipass exec gbnt-manager -- env GBNT_API_TOKEN="$API_TOKEN" /usr/local/bin/gbnt node ls || true

echo "=============================================================================="
echo "🎉 Clean 2-node cluster ready!"
echo "👑 Dashboard:   http://$MGR_PRIMARY_IP:4001   (admin / $ADMIN_PASSWORD)"
echo "🔌 API:         http://$MGR_PRIMARY_IP:4000   (Bearer $API_TOKEN)"
echo "📈 Metrics:     http://$MGR_PRIMARY_IP:4002/metrics"
echo "📊 Grafana:     http://$MGR_PRIMARY_IP:3000   | Prometheus :9090 | Jaeger :16686"
echo "🛰  Scope:       http://$MGR_PRIMARY_IP:$SCOPE_PORT"
echo "=============================================================================="
