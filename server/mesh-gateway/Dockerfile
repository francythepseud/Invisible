FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o mesh-gateway .

FROM alpine:3.19
RUN apk add --no-cache wireguard-tools iptables iproute2 ca-certificates
WORKDIR /app
COPY --from=builder /app/mesh-gateway .
RUN printf '#!/bin/sh\nset -e\necho "[ENTRYPOINT] Configurazione WireGuard..."\nip link add dev wg0 type wireguard 2>/dev/null || echo "[ENTRYPOINT] wg0 gia esistente"\necho "$SERVER_WG_PRIV" | wg set wg0 private-key /dev/stdin\nwg set wg0 listen-port 51820\nip addr add 10.7.0.1/16 dev wg0 2>/dev/null || true\nip link set wg0 up\nsysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || true\necho "[ENTRYPOINT] wg0 attivo"\necho "[ENTRYPOINT] Avvio mesh-gateway..."\nexec /app/mesh-gateway\n' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["sh", "/app/entrypoint.sh"]
