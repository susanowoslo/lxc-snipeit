#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://snipeitapp.com/

APP="SnipeIT"
var_tags="${var_tags:-asset-management;foss}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  # Ta funkcija teče ZNOTRAJ LXC
  header_info
  check_container_storage
  check_container_resources

  msg_info "Priprava na prehod na Docker Snipe-IT (pinned v7.0.9)"

  # Ustavi stari nginx/PHP (bare-metal Snipe-IT), če še teče
  if systemctl is-active --quiet nginx 2>/dev/null; then
    msg_info "Stopping nginx (stara bare-metal namestitev)"
    systemctl stop nginx || true
    systemctl disable nginx || true
    msg_ok "nginx ustavljen"
  fi

  if systemctl is-active --quiet php8.2-fpm 2>/dev/null; then
    msg_info "Stopping php-fpm"
    systemctl stop php8.2-fpm || true
    systemctl disable php8.2-fpm || true
    msg_ok "php-fpm ustavljen"
  fi

  # Namestitev Dockerja (če ni)
  if ! command -v docker >/dev/null 2>&1; then
    msg_info "Namestitev Dockerja in docker compose plugin"
    apt update
    apt -y install ca-certificates curl gnupg lsb-release

    mkdir -p /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list

    apt update
    apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
    msg_ok "Docker nameščen"
  else
    msg_ok "Docker je že nameščen"
  fi

  # Konfiguracija map
  mkdir -p /opt/snipeit
  cd /opt/snipeit

  # Osnovne spremenljivke – po potrebi po tem ročno spremeniš v docker-compose.yml
  DB_NAME="snipeit"
  DB_USER="snipeit"
  DB_PASS="ChangeMe123!"      # PRIPOROČAM, DA TO KASNEJE SPREMENIŠ
  DB_ROOT_PASS="RootPass123!" # PRIPOROČAM, DA TO KASNEJE SPREMENIŠ

  # Privzeti APP_URL na IP LXC + port 8080 (kasneje lahko ročno zamenjaš na FQDN)
  CT_IP="$(hostname -I | awk '{print $1}')"
  APP_URL_DEFAULT="http://${CT_IP}:8080"

  msg_info "Ustvarjam docker-compose.yml za Snipe-IT (pinned digest)"

  cat > /opt/snipeit/docker-compose.yml <<EOF
version: '3.8'

services:
  snipeit:
    image: snipe/snipe-it@sha256:92bfda7ac53c38c6b5a01dfaa784f57df9eddaa0aa8b664c06968a6bb1ec1df3
    container_name: snipeit
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_URL=${APP_URL_DEFAULT}
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

  msg_ok "docker-compose.yml ustvarjen"

  msg_info "Zaganjam Snipe-IT stack (docker compose up -d)"
  docker compose pull
  docker compose up -d
  msg_ok "Snipe-IT Docker stack zagnan"

  echo
  echo "======================================================="
  echo "Snipe-IT zdaj teče kot Docker container v tem LXC."
  echo "URL znotraj LAN:  http://${CT_IP}:8080"
  echo
  echo "Če uporabljaš Nginx Proxy Manager:"
  echo "  - Forward Host: ${CT_IP}"
  echo "  - Forward Port: 8080"
  echo "  - V .env / docker-compose spremeni APP_URL na tvoj FQDN (npr. https://pre.inventar.ebox.si)"
  echo "======================================================="

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
