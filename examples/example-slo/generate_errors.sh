#!/bin/bash

# Script to simulate HTTP traffic and test burning down SLO Error Budget

HOST="payment.gbnt.local"
MANAGER_IP="${1:-127.0.0.1}"

echo "======================================================="
echo "🔥 SLO Error Budget Burn-Down Traffic Generator"
echo "======================================================="
echo "Target Host  : $HOST"
echo "Manager IP   : $MANAGER_IP"
echo "======================================================="

echo "1. Generating normal traffic (HTTP 200)..."
for i in {1..20}; do
  curl -s -H "Host: $HOST" "http://$MANAGER_IP:80/" > /dev/null
  echo -n "."
  sleep 0.1
done
echo " Done!"

echo "2. Triggering HTTP 500 errors to burn Error Budget..."
for i in {1..30}; do
  curl -s -H "Host: invalid-host-test.gbnt.local" "http://$MANAGER_IP:80/500" > /dev/null
  echo -n "🔥"
  sleep 0.1
done
echo " Done!"

echo ""
echo "✅ Traffic sent! Check real-time Error Budget % remaining with:"
echo "   gbnt slo ls"
echo "   or in the Web UI: http://$MANAGER_IP:4001"
