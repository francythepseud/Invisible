#!/bin/sh
set -e

echo "[ENTRYPOINT] Configurazione WireGuard..."

# Crea interfaccia wg0 nel namespace del container
ip link add dev wg0 type wireguard 2>/dev/null || echo "[ENTRYPOINT] wg0 già esistente"

# Imposta chiave privata del server
echo "$SERVER_WG_PRIV" | wg set wg0 private-key /dev/stdin
wg set wg0 listen-port 51820

# Assegna IP del server (10.7.0.1 = gateway mesh)
ip addr add 10.7.0.1/16 dev wg0 2>/dev/null || true
ip link set wg0 up

# Abilita IP forwarding per il routing mesh
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true

echo "[ENTRYPOINT] wg0 attivo: $(wg show wg0 public-key)"
echo "[ENTRYPOINT] Avvio mesh-gateway..."

exec /app/mesh-gateway
