#!/usr/bin/env bash

set -euo pipefail

PROFILE="agonops"
FRONTEND_URL="http://localhost"
GAME_PORT="7021"

echo "================================="
echo " AgonOps Local Environment"
echo "================================="

echo "[1/7] Starting Minikube..."
minikube start -p "$PROFILE"

echo "[2/7] Waiting for Kubernetes..."
kubectl wait \
  --for=condition=Ready \
  node \
  --all \
  --timeout=120s

echo "[3/7] Waiting for application workloads..."

kubectl rollout status deployment/frontend --timeout=120s
kubectl rollout status deployment/director --timeout=120s
kubectl rollout status deployment/mmf --timeout=120s

echo "[4/7] Starting Minikube tunnel..."

# Clean up tunnel from previous scripted run if necessary
if [ -f /tmp/agonops-tunnel.pid ]; then
    OLD_PID=$(cat /tmp/agonops-tunnel.pid)

    if kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
    fi

    rm -f /tmp/agonops-tunnel.pid
fi

rm -f /tmp/agonops-tunnel.log

nohup minikube tunnel -p "$PROFILE" \
  > /tmp/agonops-tunnel.log 2>&1 < /dev/null &

TUNNEL_PID=$!
echo "$TUNNEL_PID" > /tmp/agonops-tunnel.pid

sleep 2

echo "[5/7] Waiting for frontend..."

for i in {1..45}; do

    if curl -fsS --max-time 2 "$FRONTEND_URL" >/dev/null 2>&1; then
        echo "Frontend responding."
        break
    fi

    if [ "$i" -eq 45 ]; then
        echo "ERROR: Frontend did not become reachable."
        echo ""
        echo "Tunnel log:"
        cat /tmp/agonops-tunnel.log
        exit 1
    fi

    sleep 1
done

echo ""
echo "Opening two game clients..."

powershell.exe -NoProfile -Command \
  "Start-Process 'chrome.exe' -ArgumentList '--new-window','$FRONTEND_URL'" \
  >/dev/null 2>&1 || true

sleep 1

powershell.exe -NoProfile -Command \
  "Start-Process 'chrome.exe' -ArgumentList '--incognito','--new-window','$FRONTEND_URL'" \
  >/dev/null 2>&1 || true

echo ""
echo "======================================================"
echo " ACTION REQUIRED"
echo "======================================================"
echo ""
echo "Click FIND GAME in BOTH browser windows."
echo ""
echo "The automatic connection may show EOF locally."
echo "That is expected on this Windows/Minikube setup."
echo ""
echo "Waiting for Open Match + Director to allocate a server..."
echo ""

echo "[6/7] Waiting for Allocated GameServer..."

GAMESERVER=""

for i in {1..120}; do

    GAMESERVER=$(kubectl get gameservers \
      -o jsonpath='{range .items[?(@.status.state=="Allocated")]}{.metadata.name}{"\n"}{end}' \
      2>/dev/null \
      | head -n1 || true)

    if [ -n "${GAMESERVER:-}" ]; then
        break
    fi

    sleep 1
done

if [ -z "${GAMESERVER:-}" ]; then
    echo ""
    echo "ERROR: No GameServer was allocated within 120 seconds."
    echo ""
    echo "Make sure Find Game was clicked in BOTH browser windows."
    echo ""
    kubectl get gameservers
    exit 1
fi

echo "Allocated GameServer detected:"
echo "  $GAMESERVER"

echo "$GAMESERVER" > /tmp/agonops-gameserver.name

echo "[7/7] Creating local GameServer route..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: agonops-gameserver
spec:
  type: LoadBalancer
  selector:
    agones.dev/gameserver: $GAMESERVER
  ports:
    - name: game
      protocol: TCP
      port: $GAME_PORT
      targetPort: 2156
EOF

echo "Waiting for GameServer endpoint..."

for i in {1..30}; do

    ENDPOINT=$(kubectl get endpoints agonops-gameserver \
      -o jsonpath='{.subsets[0].addresses[0].ip}' \
      2>/dev/null || true)

    if [ -n "${ENDPOINT:-}" ]; then
        break
    fi

    sleep 1
done

if [ -z "${ENDPOINT:-}" ]; then
    echo "ERROR: GameServer service has no endpoint."
    kubectl get endpoints agonops-gameserver -o wide
    exit 1
fi

echo "GameServer endpoint:"
echo "  $ENDPOINT:2156"

echo "Waiting for localhost LoadBalancer..."

EXTERNAL_IP=""

for i in {1..45}; do

    EXTERNAL_IP=$(kubectl get service agonops-gameserver \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' \
      2>/dev/null || true)

    if [ "$EXTERNAL_IP" = "127.0.0.1" ]; then
        break
    fi

    sleep 1
done

if [ "$EXTERNAL_IP" != "127.0.0.1" ]; then
    echo "ERROR: Local GameServer LoadBalancer did not become available."
    kubectl get service agonops-gameserver -o wide
    exit 1
fi

echo "Waiting for TCP GameServer..."

READY="False"

for i in {1..30}; do

    READY=$(powershell.exe -NoProfile -Command \
      "(Test-NetConnection 127.0.0.1 -Port $GAME_PORT -WarningAction SilentlyContinue).TcpTestSucceeded" \
      2>/dev/null | tr -d '\r')

    if [ "$READY" = "True" ]; then
        break
    fi

    sleep 1
done

if [ "$READY" != "True" ]; then
    echo "ERROR: GameServer is not reachable on localhost:$GAME_PORT."
    exit 1
fi

echo ""
echo "================================="
echo " AgonOps is READY"
echo "================================="
echo ""
echo "Frontend:"
echo "  $FRONTEND_URL"
echo ""
echo "Allocated GameServer:"
echo "  $GAMESERVER"
echo ""
echo "Local GameServer:"
echo "  127.0.0.1:$GAME_PORT"
echo ""
echo "NEXT:"
echo "  In BOTH browser windows:"
echo ""
echo "  Connect To Server"
echo "  127.0.0.1:$GAME_PORT"
echo ""
echo "================================="