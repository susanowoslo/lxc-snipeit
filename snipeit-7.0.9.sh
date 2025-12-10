#!/usr/bin/env bash
# LXC + Docker + Snipe-IT v7.0.9
# Zaženi na Proxmox hostu: ./snipeit-docker-709.sh

set -e

CTID=${CTID:-0}

echo "=== Snipe-IT Docker installer (v7.0.9) ==="
echo ""

if [ "$CTID" = "0" ]; then
    read -p "Vnesi CTID novega LXC (primer: 120): " CTID
fi

echo "Ustvarjam LXC container $CTID ..."

pct create $CTID local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
    --hostname snipeit \
    --cores 2 \
    --memory 2048 \
    --swap 512 \
    --rootfs local-lvm:8 \
    --unprivileged 1 \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --features nesting=1,keyctl=1

pct start $CTID
sleep 4

echo "Namestitev Docker-ja ..."
pct exec $CTID -- bash -c "apt update && apt install -y curl ca-certificates gnupg lsb-release"

pct exec $CTID -- bash -c "
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

echo "Ustvarjam mapo za Snipe-IT ..."
pct exec $CTID -- mkdir -p /opt/snipeit

echo "Zapisujem docker-compose.yml ..."

pct exec $CTID -- bash -c "cat > /opt/snipeit/docker-compose.yml << 'EOF'
version: '3.8'

services:
  snipeit:
    image: snipe/snipe-it:v7.0.9
    container_name: snipeit
    restart: unless-stopped
    ports:
      - '8080:80'
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_URL=http://YOUR-IP-OR-DOMAIN
      - APP_TIMEZONE=Europe/Ljubljana
      - APP_LOCALE=sl-SI

      # DB nastavitve
      - DB_CONNECTION=mysql
      - DB_HOST=db
      - DB_DATABASE=snipeit
      - DB_USERNAME=snipeit
      - DB_PASSWORD=ChangeMe123!

    depends_on:
      - db
    volumes:
      - ./uploads:/var/lib/snipeit

  db:
    image: mariadb:10.6
    container_name: snipeit-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=RootPass123!
      - MYSQL_DATABASE=snipeit
      - MYSQL_USER=snipeit
      - MYSQL_PASSWORD=ChangeMe123!
    volumes:
      - ./mysql:/var/lib/mysql
EOF
"

echo "Zagon Snipe-IT ..."
pct exec $CTID -- bash -c "cd /opt/snipeit && docker compose up -d"

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo ""
echo "============================================"
echo "Snipe-IT 7.0.9 Docker je nameščen!"
echo "Dostop: http://$IP:8080"
echo ""
echo "Za reverse proxy (NPM) uporabi:"
echo "IP: $IP"
echo "PORT: 8080"
echo "============================================"
