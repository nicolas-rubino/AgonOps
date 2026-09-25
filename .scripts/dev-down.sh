#!/usr/bin/env bash

set -u

PROFILE="agonops"

echo "=== Stopping AgonOps ==="

kubectl delete service agonops-gameserver \
  --ignore-not-found \
  >/dev/null 2>&1 || true

if [ -f /tmp/agonops-tunnel.pid ]; then

    TUNNEL_PID=$(cat /tmp/agonops-tunnel.pid)

    kill "$TUNNEL_PID" \
      2>/dev/null || true

    rm -f /tmp/agonops-tunnel.pid
fi

if [ -f /tmp/agonops-gameserver.name ]; then
    rm -f /tmp/agonops-gameserver.name
fi

minikube stop -p "$PROFILE"

echo ""
echo "AgonOps stopped."