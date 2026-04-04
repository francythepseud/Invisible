#!/bin/bash
# setup.sh — configura e blinda il VPS Invisible dalla prima volta
# Eseguire come root su Ubuntu 22.04+ / 24.04
# Usage: bash setup.sh <your-domain.com>

set -euo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

echo "=== Invisible VPS Setup ==="
echo "Dominio: $DOMAIN"

# ── 1. Aggiornamento sistema ──────────────────────────────────────────────────
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y --no-install-recommends \
  wireguard wireguard-tools \
  docker.io docker-compose-plugin \
  certbot nginx-full \
  ufw fail2ban \
  unattended-upgrades apt-listchanges \
  golang-go \
  curl openssl

# ── 2. Unattended upgrades (patch di sicurezza automatiche) ──────────────────
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable unattended-upgrades
echo "[OK] Aggiornamenti di sicurezza automatici attivi"

# ── 3. Kernel hardening (sysctl) ─────────────────────────────────────────────
cat > /etc/sysctl.d/99-invisible-hardening.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
kernel.printk = 3 4 1 3
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
EOF
sysctl -p /etc/sysctl.d/99-invisible-hardening.conf
echo "[OK] Kernel hardening applicato"

# ── 4. SSH hardening ──────────────────────────────────────────────────────────
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
AddressFamily inet
ListenAddress 0.0.0.0

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
GatewayPorts no

LogLevel VERBOSE
SyslogFacility AUTH

KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com

Subsystem sftp /usr/lib/openssh/sftp-server
EOF
systemctl reload sshd
echo "[OK] SSH hardening: solo chiavi publiche, no root, algoritmi moderni"

# ── 5. WireGuard server keypair ───────────────────────────────────────────────
WG_PRIV=$(wg genkey)
WG_PUB=$(echo "$WG_PRIV" | wg pubkey)

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.7.0.1/16
ListenPort = 51820
PrivateKey = $WG_PRIV
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
chmod 600 /etc/wireguard/wg0.conf

systemctl enable wg-quick@wg0
systemctl start  wg-quick@wg0
echo "[OK] WireGuard server avviato (pub: $WG_PUB)"

# ── 6. Firewall UFW ───────────────────────────────────────────────────────────
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

ufw limit 22/tcp comment 'SSH rate-limited'
ufw allow 80/tcp  comment 'HTTP (redirect to HTTPS)'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 51820/udp comment 'WireGuard VPN'

cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

ufw --force enable
echo "[OK] Firewall UFW attivo — solo SSH/80/443/51820 aperti"

# ── 7. Fail2ban ───────────────────────────────────────────────────────────────
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = ufw

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 3600

[nginx-badbots]
enabled  = true
port     = http,https
filter   = nginx-badbots
logpath  = /var/log/nginx/access.log
maxretry = 2
bantime  = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "[OK] Fail2ban configurato (SSH ban 24h, nginx anti-bot)"

# ── 8. Certificato TLS con Let's Encrypt ─────────────────────────────────────
systemctl stop nginx 2>/dev/null || true

certbot certonly --standalone --non-interactive --agree-tos \
  --email "admin@$DOMAIN" -d "$DOMAIN" \
  --rsa-key-size 4096

mkdir -p ./data/nginx/certs
ln -sf /etc/letsencrypt/live/$DOMAIN/fullchain.pem ./data/nginx/certs/fullchain.pem
ln -sf /etc/letsencrypt/live/$DOMAIN/privkey.pem   ./data/nginx/certs/privkey.pem

echo "0 3 * * * root certbot renew --quiet --pre-hook 'docker compose stop nginx' --post-hook 'docker compose start nginx'" \
  > /etc/cron.d/certbot-renew
echo "[OK] TLS Let's Encrypt configurato (rsa-4096, rinnovo automatico)"

# ── 9. File .env per docker-compose ──────────────────────────────────────────
VPS_IP=$(curl -s https://api.ipify.org)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 40)
JWT_SECRET=$(openssl rand -base64 48 | tr -d '/+=' | head -c 64)
ADMIN_TOKEN=$(openssl rand -hex 32)

cat > .env << EOF
VPS_IP=$VPS_IP
SERVER_ENDPOINT=${VPS_IP}:51820
SERVER_WG_PRIV=$WG_PRIV
SERVER_WG_PUB=$WG_PUB
DOMAIN=$DOMAIN
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ADMIN_TOKEN=$ADMIN_TOKEN
EOF

chmod 600 .env
echo "[OK] .env creato con credenziali generate (NON committare su git)"

# ── 10. Docker: build e avvio ─────────────────────────────────────────────────
systemctl restart docker
sleep 3

docker compose build
docker compose up -d

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           INVISIBLE VPS — SETUP COMPLETATO                  ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  VPS IP pubblico:       $VPS_IP"
echo "║  WireGuard UDP:         $VPS_IP:51820"
echo "║  WireGuard server pub:  $WG_PUB"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ENDPOINT APP FLUTTER                                        ║"
echo "║  Relay WSS:             wss://$DOMAIN/v1/relay"
echo "║  Signaling WSS:         wss://$DOMAIN/v1/signal"
echo "║  Mesh Gateway HTTPS:    https://$DOMAIN/v1/mesh"
echo "║  ToS URL:               https://$DOMAIN/v1/tos"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ADMIN DASHBOARD                                             ║"
echo "║  URL:   https://$DOMAIN/admin/?token=$ADMIN_TOKEN"
echo "║  Token: $ADMIN_TOKEN"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  SICUREZZA ATTIVATA                                          ║"
echo "║  [OK] SSH: solo chiavi pubbliche, no root login              ║"
echo "║  [OK] UFW: solo 22/80/443/51820 aperti                       ║"
echo "║  [OK] Fail2ban: SSH ban 24h, nginx anti-bot                  ║"
echo "║  [OK] Kernel hardening: anti-SYN flood, anti-spoof           ║"
echo "║  [OK] TLS 1.3 + RSA-4096 + rinnovo automatico               ║"
echo "║  [OK] Docker: log rotation attiva                            ║"
echo "║  [OK] Aggiornamenti sicurezza automatici                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  DA FARE DOPO QUESTO SETUP                                   ║"
echo "║  1. Aggiungi la tua chiave SSH pubblica in ~/.ssh/authorized_keys"
echo "║  2. Verifica SSH funziona con chiave PRIMA di chiudere questa sessione"
echo "║  3. Aggiorna lib/utils/constants.dart nell'app Flutter       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
