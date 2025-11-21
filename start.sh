#!/bin/sh
set -e
REPO_DIR=$(dirname "$(realpath "$0")")

sudo apt-get update
sudo apt-get upgrade --yes

echo "### Disable swap ###"
sudo systemctl mask dev-zram0.swap
sudo systemctl mask systemd-zram-setup@zram0.service
sudo systemctl daemon-reload

echo "### Installing nginx ###"
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

echo "### Installing fail2ban ###"
sudo apt-get install -y fail2ban
sudo cp "$REPO_DIR/config/fail2ban/jail.local" /etc/fail2ban/jail.local
sudo cp "$REPO_DIR/config/fail2ban/filter/nginx-404.conf" /etc/fail2ban/filter.d/nginx-404.conf
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "### Installing firewall ###"
sudo apt-get install -y ufw
# UFW Reset (alle alten Regeln löschen)
sudo ufw --force reset

# Standardregeln: alles blocken
sudo ufw default deny incoming
sudo ufw default deny outgoing

# SSH nur vom Heimnetz erlauben
sudo ufw allow from 192.168.178.0/24 to any port 22 proto tcp

# HTTPS für alle erlauben
sudo ufw allow 443/tcp

# UFW aktivieren
sudo ufw --force enable

# --- Cronjobs einrichten ---
echo "Installiere Cronjobs..."
CRON_DIR="$REPO_DIR/config/cron"

sudo cp "$CRON_DIR/update-ionos-ddns.sh" /usr/local/bin/update-ionos-ddns.sh
sudo chmod 644 /usr/local/bin/update-ionos-ddns.sh
sudo cp "$CRON_DIR/update-ionos-ddns-wrapper.sh" /usr/local/bin/update-ionos-ddns-wrapper.sh
sudo chmod 644 /usr/local/bin/update-ionos-ddns-wrapper.sh
sudo cp "$CRON_DIR/update-status-json.sh" /usr/local/bin/update-status-json.sh
sudo chmod 644 /usr/local/bin/update-status-json.sh
sudo cp "$CRON_DIR/update-status-json-wrapper.sh" /usr/local/bin/update-status-json-wrapper.sh
sudo chmod 644 /usr/local/bin/update-status-json-wrapper.sh
if [ "$IONOS_DDNS_ACTIVATE" = "true" ]; then
  echo "IONOS DDNS aktiviert, Cronjob wird gesetzt."
  sudo cp "$CRON_DIR/update-ionos-ddns" /etc/cron.d/
else
  echo "IONOS DDNS deaktiviert, Cronjob wird nicht gesetzt."
fi
sudo cp "$CRON_DIR/update-status-json" /etc/cron.d/

# Berechtigungen setzen
sudo chmod 644 /etc/cron.d/*
sudo systemctl restart cron || true
echo "Cronjobs installiert:"
ls -l /etc/cron.d/