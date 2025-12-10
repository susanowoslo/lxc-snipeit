#!/usr/bin/env bash
# Proxmox LXC + Docker + Snipe-IT (pinned v7.0.9 digest)
# Zaženi na Proxmox hostu: chmod +x snipeit-docker-709.sh && ./snipeit-docker-709.sh

set -euo pipefail

TEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"   # po potrebi spremeni storage/template
STORAGE="local-lvm"                                              # ZFS/LVM storage za rootfs
RAM="2048"                                                       # MB
DISK="16"                                                        # GB

echo "=== Snipe-IT Docker LXC installer (v7.0.9 – pinned digest) ==="
echo

read -rp "Vnesi CTID novega LXC (npr. 120): " CTID
read -rp "Vnesi ime hosta (npr. snipeit): " HOSTNAME
read -rp "APP_URL (npr. https://pre.inventar.ebox.si ali http://10.0.0.50:8080): " APP_URL

# DB gesla – PRILAGODI
DB_NAME="snipeit"
DB_USER="snipeit"
DB_PASS="ChangeMe123!"      # spremeni
DB_ROOT_PASS="RootPass123!" # spremeni

echo
echo "Ustvarjam LXC CTID=${CTID}, HOSTNAME=${HOSTNAME} ..."
pct create "${CTID}" "${TEMPLATE}" \
  --hostname "${HOSTNAME}" \
  --cores 2 \
  --memory "${RAM}" \
  --swap 512 \
  --rootfs "${STORAGE}:${DISK}" \
  --unprivileged 1 \
  --password '' \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1,keyctl=1

pct start "${CTID}"
echo "Čakam, da se LXC zažene ..."
sleep 5

echo "Posodabljam sistem in nameščam Docker v CT ${CTID} ..."
pct exec "${CTID}" -- bash -c "
set -e
apt update
apt -y upgrade
apt -y install ca-certificates curl gnupg lsb-release

mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
"

echo "Ustvarjam /opt/snipeit v CT ..."
pct exec "${CTID}" -- mkdir -p /opt/snipeit

echo "Pišem docker-compose.yml v CT ..."
pct exec "${CTID}" -- bash -c "cat > /opt/snipeit/docker-compose.yml <<EOF
version: '3.8'

services:
  snipeit:
    image: snipe/snipe-it@sha256:92bfda7ac53c38c6b5a01dfaa784f57df9eddaa0aa8b664c06968a6bb1ec1df3
    container_name: snipeit
    restart: unless-stopped
    ports:
      - '8080:80'
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_URL=${APP_URL}
      - APP_TIMEZONE=Europe/Ljubljana
      - APP_LOCALE=sl-SI

      - DB_CONNECTION=mysql
      - DB_HOST=db
      - DB_DATABASE=${DB_NAME}
      - DB_USERNAME=${DB_USER}
      - DB_PASSWORD=${DB_PASS}

    depends_on:
      - db
    volumes:
      - ./uploads:/var/lib/snipeit

  db:
    image: mariadb:10.6
    container_name: snipeit-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}
      - MYSQL_DATABASE=${DB_NAME}
      - MYSQL_USER=${DB_USER}
      - MYSQL_PASSWORD=${DB_PASS}
    volumes:
      - ./mysql:/var/lib/mysql
EOF
"

echo "Zaganjam Snipe-IT stack (docker compose up -d) ..."
pct exec "${CTID}" -- bash -c "cd /opt/snipeit && docker compose pull && docker compose up -d"

IP=$(pct exec "${CTID}" -- hostname -I | awk '{print $1}')

echo
echo "========================================================"
echo "Snipe-IT Docker (v7.0.9, pinned digest) je zagnan."
echo "LXC CTID: ${CTID}"
echo "LXC IP:   ${IP}"
echo
echo "Dostop neposredno:  http://${IP}:8080"
echo
echo "APP_URL nastavljeno na: ${APP_URL}"
echo "Če si v APP_URL dal https domeno, daj pred LXC še reverse proxy (npr. Nginx Proxy Manager)"
echo "Forward host: ${IP}, port: 8080"
echo "========================================================"
