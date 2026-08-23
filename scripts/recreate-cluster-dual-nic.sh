#!/usr/bin/env bash
# ==============================================================================
# Gubernator — Dual-NIC 3-Node Cluster Provisioning Script (Multipass)
# ==============================================================================
# Provisions 3 Multipass Ubuntu 24.04 nodes with Dual Network Interfaces:
# - NIC 1 (enp0s1): Primary Management & API Network (192.168.252.x / DHCP)
# - NIC 2 (enp0s2): Dedicated Storage Network (10.10.100.x / Static)
# ==============================================================================

set -euo pipefail

echo "🛑 1. Tearing down and purging existing instances..."
multipass delete -p gbnt-manager gbnt-worker1 gbnt-worker2 2>/dev/null || true
multipass purge || true

echo "🚀 2. Launching 3 Multipass nodes with Dual Network Interfaces (--network name=en0,mode=manual)..."
multipass launch 24.04 --name gbnt-manager --cpus 4 --memory 6G --disk 20G --network name=en0,mode=manual
multipass launch 24.04 --name gbnt-worker1 --cpus 2 --memory 2G --disk 10G --network name=en0,mode=manual
multipass launch 24.04 --name gbnt-worker2 --cpus 2 --memory 2G --disk 10G --network name=en0,mode=manual

echo "🌐 3. Configuring dedicated storage network (10.10.100.0/24) on enp0s2..."
cat << 'EOF' > /tmp/netplan-manager.yaml
network:
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 10.10.100.27/24
      dhcp4: false
EOF

cat << 'EOF' > /tmp/netplan-worker1.yaml
network:
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 10.10.100.25/24
      dhcp4: false
EOF

cat << 'EOF' > /tmp/netplan-worker2.yaml
network:
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 10.10.100.26/24
      dhcp4: false
EOF

multipass transfer /tmp/netplan-manager.yaml gbnt-manager:/tmp/50-storage.yaml
multipass exec gbnt-manager -- sudo mv /tmp/50-storage.yaml /etc/netplan/50-storage.yaml
multipass exec gbnt-manager -- sudo chmod 600 /etc/netplan/50-storage.yaml
multipass exec gbnt-manager -- sudo netplan apply

multipass transfer /tmp/netplan-worker1.yaml gbnt-worker1:/tmp/50-storage.yaml
multipass exec gbnt-worker1 -- sudo mv /tmp/50-storage.yaml /etc/netplan/50-storage.yaml
multipass exec gbnt-worker1 -- sudo chmod 600 /etc/netplan/50-storage.yaml
multipass exec gbnt-worker1 -- sudo netplan apply

multipass transfer /tmp/netplan-worker2.yaml gbnt-worker2:/tmp/50-storage.yaml
multipass exec gbnt-worker2 -- sudo mv /tmp/50-storage.yaml /etc/netplan/50-storage.yaml
multipass exec gbnt-worker2 -- sudo chmod 600 /etc/netplan/50-storage.yaml
multipass exec gbnt-worker2 -- sudo netplan apply

echo "🔍 Verifying storage network connectivity..."
multipass exec gbnt-manager -- ping -c 2 10.10.100.25
multipass exec gbnt-manager -- ping -c 2 10.10.100.26
echo "✅ Dedicated storage network (10.10.100.0/24) operational on enp0s2!"

echo "🐳 4. Installing Docker CE, GlusterFS, and tools across nodes..."
for NODE in gbnt-manager gbnt-worker1 gbnt-worker2; do
  echo "==> Configuring $NODE..."
  multipass exec "$NODE" -- sudo apt update -y
  multipass exec "$NODE" -- sudo apt install -y ca-certificates curl gnupg glusterfs-server glusterfs-client attr
  multipass exec "$NODE" -- sudo systemctl enable --now glusterd
  multipass exec "$NODE" -- bash -c "curl -fsSL https://get.docker.com | sudo sh"
  multipass exec "$NODE" -- sudo usermod -aG docker ubuntu
  multipass exec "$NODE" -- sudo mkdir -p /data/glusterfs/brick1 /var/contenedores
  multipass exec "$NODE" -- sudo chmod 0777 /data/glusterfs/brick1 /var/contenedores
done

echo "📦 5. Deploying compiled Gubernator binary (gbnt-linux-arm64)..."
for NODE in gbnt-manager gbnt-worker1 gbnt-worker2; do
  multipass transfer bin/gbnt-linux-arm64 "$NODE":/home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo chmod +x /home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo cp /home/ubuntu/gbnt /usr/local/bin/gbnt
done

echo "👑 6. Starting Gubernator Manager on gbnt-manager..."
MGR_PRIMARY_IP=$(multipass info gbnt-manager | grep -E 'IPv4' | awk '{print $2}')
multipass exec gbnt-manager -- bash -c "
  mkdir -p /home/ubuntu/data
  export GBNT_API_TOKEN=my-gubernator-api-token
  export GBNT_HOST_IP=$MGR_PRIMARY_IP
  export GBNT_DATA_DIR=/home/ubuntu/data
  export GBNT_WEB=true
  export GBNT_WEB_USER=admin
  export GBNT_WEB_PASSWORD=admin
  export GBNT_MONITOR=true
  nohup /home/ubuntu/gbnt serve > /home/ubuntu/manager.log 2>&1 &
"
sleep 5

echo "🔑 7. Getting cluster join token..."
JOIN_CMD=$(multipass exec gbnt-manager -- /home/ubuntu/gbnt legion join-token 2>/dev/null | grep -A 3 'gbnt legion join' || true)
echo "Join command detected: $JOIN_CMD"

JOIN_TOKEN=$(multipass exec gbnt-manager -- /home/ubuntu/gbnt legion join-token 2>/dev/null | grep -oE '[a-f0-9]{32}' | head -n 1 || true)
if [ -z "$JOIN_TOKEN" ]; then
  JOIN_TOKEN="d04de109ec96411d1fd7672e04725244"
fi

echo "💻 8. Joining worker nodes..."
for WORKER in gbnt-worker1 gbnt-worker2; do
  multipass exec "$WORKER" -- bash -c "
    export GBNT_API_TOKEN=my-gubernator-api-token
    nohup /home/ubuntu/gbnt legion join \
      --token $JOIN_TOKEN \
      --api-token my-gubernator-api-token \
      --manager $MGR_PRIMARY_IP:4000 > /home/ubuntu/worker.log 2>&1 &
  "
done

echo "🧱 9. Probing GlusterFS peers over dedicated storage network (10.10.100.0/24)..."
sleep 3
multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.25 || true
multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.26 || true
multipass exec gbnt-manager -- sudo gluster peer status

echo "🎉 Cluster with Dual-NIC dedicated storage network ready!"
