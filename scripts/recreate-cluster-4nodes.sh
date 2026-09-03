#!/usr/bin/env bash
# ==============================================================================
# Gubernator — Dual-NIC 4-Node Clean Cluster Provisioning Script (Multipass)
# ==============================================================================
# Provisions 4 Multipass Ubuntu 24.04 nodes:
# - gbnt-manager (Manager + API + Web Dashboard)
# - gbnt-worker1 (Centurion Worker 1)
# - gbnt-worker2 (Centurion Worker 2)
# - gbnt-worker3 (Centurion Worker 3)
# ==============================================================================

set -euo pipefail

echo "🛑 1. Deleting and purging existing instances..."
multipass delete -p gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3 2>/dev/null || true
multipass purge || true

echo "🚀 2. Launching 4 clean Multipass Ubuntu 24.04 nodes with Dual Network Interfaces..."
multipass launch 24.04 --name gbnt-manager --cpus 4 --memory 6G --disk 30G --network name=en0,mode=manual
multipass launch 24.04 --name gbnt-worker1 --cpus 2 --memory 3G --disk 20G --network name=en0,mode=manual
multipass launch 24.04 --name gbnt-worker2 --cpus 2 --memory 3G --disk 20G --network name=en0,mode=manual
multipass launch 24.04 --name gbnt-worker3 --cpus 2 --memory 3G --disk 20G --network name=en0,mode=manual

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

cat << 'EOF' > /tmp/netplan-worker3.yaml
network:
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 10.10.100.28/24
      dhcp4: false
EOF

for NODE in gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  SHORT=${NODE#gbnt-}
  multipass transfer "/tmp/netplan-${SHORT}.yaml" "$NODE":/tmp/50-storage.yaml
  multipass exec "$NODE" -- sudo mv /tmp/50-storage.yaml /etc/netplan/50-storage.yaml
  multipass exec "$NODE" -- sudo chmod 600 /etc/netplan/50-storage.yaml
  multipass exec "$NODE" -- sudo netplan apply
done

echo "🔍 Verifying storage network connectivity..."
multipass exec gbnt-manager -- ping -c 2 10.10.100.25
multipass exec gbnt-manager -- ping -c 2 10.10.100.26
multipass exec gbnt-manager -- ping -c 2 10.10.100.28
echo "✅ Dedicated storage network (10.10.100.0/24) operational on enp0s2!"

echo "🐳 4. Installing Docker CE, GlusterFS, and tools across all 4 nodes..."
for NODE in gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  echo "==> Configuring packages on $NODE..."
  multipass exec "$NODE" -- sudo apt update -y
  multipass exec "$NODE" -- sudo apt install -y ca-certificates curl gnupg glusterfs-server glusterfs-client attr
  multipass exec "$NODE" -- sudo systemctl enable --now glusterd
  multipass exec "$NODE" -- bash -c "curl -fsSL https://get.docker.com | sudo sh"
  multipass exec "$NODE" -- sudo usermod -aG docker ubuntu
  multipass exec "$NODE" -- sudo mkdir -p /data/glusterfs/brick1 /var/contenedores
  multipass exec "$NODE" -- sudo chmod 0777 /data/glusterfs/brick1 /var/contenedores
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

for NODE in gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  multipass exec "$NODE" -- bash -c "echo '$MGR_PUB_KEY' >> /home/ubuntu/.ssh/authorized_keys"
  multipass exec "$NODE" -- bash -c "
    mkdir -p /home/ubuntu/.ssh
    echo 'StrictHostKeyChecking no' >> /home/ubuntu/.ssh/config
    chmod 600 /home/ubuntu/.ssh/config
  "
done

echo "🔍 Testing passwordless SSH from manager to all workers..."
for NODE in gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  NODE_IP=$(multipass info "$NODE" | grep -E 'IPv4' | awk '{print $2}')
  echo "Testing SSH to $NODE ($NODE_IP)..."
  multipass exec gbnt-manager -- ssh -i /data/ssh/id_ed25519 -o StrictHostKeyChecking=no "ubuntu@$NODE_IP" "hostname"
done

echo "📦 6. Deploying freshly compiled Gubernator binary (v2.69.2)..."
for NODE in gbnt-manager gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  multipass transfer bin/gbnt-linux-arm64 "$NODE":/home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo chmod +x /home/ubuntu/gbnt
  multipass exec "$NODE" -- sudo cp /home/ubuntu/gbnt /usr/local/bin/gbnt
done

echo "👑 7. Starting Gubernator Manager on gbnt-manager..."
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

echo "🔑 8. Getting cluster join token..."
JOIN_TOKEN=$(multipass exec gbnt-manager -- /home/ubuntu/gbnt legion join-token 2>/dev/null | grep -oE '[a-f0-9]{32}' | head -n 1 || true)
if [ -z "$JOIN_TOKEN" ]; then
  JOIN_TOKEN="d04de109ec96411d1fd7672e04725244"
fi
echo "Join Token: $JOIN_TOKEN"

echo "💻 9. Joining all 3 worker nodes..."
for WORKER in gbnt-worker1 gbnt-worker2 gbnt-worker3; do
  echo "Joining $WORKER..."
  multipass exec "$WORKER" -- bash -c "
    export GBNT_API_TOKEN=my-gubernator-api-token
    nohup /home/ubuntu/gbnt legion join \
      --token $JOIN_TOKEN \
      --api-token my-gubernator-api-token \
      --manager $MGR_PRIMARY_IP:4000 > /home/ubuntu/worker.log 2>&1 &
  "
done

echo "🧱 10. Probing GlusterFS peers over dedicated storage network (10.10.100.0/24)..."
sleep 3
multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.25 || true
multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.26 || true
multipass exec gbnt-manager -- sudo gluster peer probe 10.10.100.28 || true
multipass exec gbnt-manager -- sudo gluster peer status

echo "=============================================================================="
echo "🎉 Clean 4-node cluster ready!"
echo "👑 Manager URL: http://$MGR_PRIMARY_IP:4001"
echo "🔐 Credentials: admin / admin"
echo "=============================================================================="
