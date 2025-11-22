#!/bin/sh
set -e
REPO_DIR=$(dirname "$(realpath "$0")")
ENV_FILE="$REPO_DIR/config/.env"
CRON_DIR="$REPO_DIR/config/cron"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

sudo apt-get update
sudo apt-get upgrade --yes

echo "###################################"
echo "### Disable swap ###"
echo "###################################"
sudo systemctl mask dev-zram0.swap
sudo systemctl mask systemd-zram-setup@zram0.service
sudo systemctl daemon-reload

echo "###################################"
echo "### Installing nginx ###"
echo "###################################"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
sudo cp -r "$REPO_DIR/config/nginx/snippets/" /etc/nginx/
sudo cp -r "$REPO_DIR/config/nginx/ssl/" /etc/nginx/
sudo mv /etc/nginx/ssl/larsfrauenrath.crt /etc/ssl/certs/larsfrauenrath.crt
sudo mv /etc/nginx/ssl/larsfrauenrath.key /etc/ssl/private/larsfrauenrath.key;
sudo mv /etc/nginx/ssl/dhparam.pem /etc/ssl/certs/dhparam.pem;
sudo cp "$REPO_DIR/config/nginx/diefrauenraths.de" /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/diefrauenraths.de /etc/nginx/sites-enabled/diefrauenraths.de
sudo cp "$REPO_DIR/config/nginx/status" /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/status /etc/nginx/sites-enabled/status
sudo rm /etc/nginx/sites-enabled/default
sudo systemctl stop nginx
sudo systemctl enable nginx
sudo systemctl start nginx

echo "###################################"
echo "### Installing fail2ban ###"
echo "###################################"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
sudo cp "$REPO_DIR/config/fail2ban/jail.local" /etc/fail2ban/jail.local
sudo cp "$REPO_DIR/config/fail2ban/filter/nginx-404.conf" /etc/fail2ban/filter.d/nginx-404.conf
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "###################################"
echo "### Installing firewall ###"
echo "###################################"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
# UFW Reset (alle alten Regeln löschen)
sudo ufw --force reset
sudo ufw --force disable

# Standardregeln: alles blocken
sudo ufw default deny incoming
sudo ufw default deny outgoing
# DNS für Namensauflösung
sudo ufw allow out 53/tcp
sudo ufw allow out 53/udp

# HTTPS für Git, apt etc.
sudo ufw allow out 443/tcp
sudo ufw allow out 80/tcp

# SSH nur vom Heimnetz erlauben
sudo ufw allow from 192.168.178.0/24 to any port 22 proto tcp

# HTTPS für alle erlauben
sudo ufw allow 443/tcp

# --- Cronjobs einrichten ---
echo "###################################"
echo "Installiere Cronjobs..."
echo "###################################"

sudo cp "$CRON_DIR/update-ionos-ddns.sh" /usr/local/bin/update-ionos-ddns.sh
sudo chmod +x /usr/local/bin/update-ionos-ddns.sh
sudo cp "$CRON_DIR/update-ionos-ddns-wrapper.sh" /usr/local/bin/update-ionos-ddns-wrapper.sh
sudo chmod +x /usr/local/bin/update-ionos-ddns-wrapper.sh
sudo mkdir -p /var/www/status
sudo cp "$CRON_DIR/update-status-json.sh" /usr/local/bin/update-status-json.sh
sudo chmod +x /usr/local/bin/update-status-json.sh
sudo cp "$CRON_DIR/update-status-json-wrapper.sh" /usr/local/bin/update-status-json-wrapper.sh
sudo chmod +x /usr/local/bin/update-status-json-wrapper.sh
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

echo "###################################"
echo "Desktop, Druck und andere unnötige Services deaktivieren"
echo "###################################"
# GUI / Display Manager
sudo systemctl disable lightdm.service
sudo systemctl stop lightdm.service

# Audio / Test
sudo systemctl disable glamor-test.service
sudo systemctl stop glamor-test.service
sudo systemctl disable rp1-test.service
sudo systemctl stop rp1-test.service
sudo systemctl disable alsa-restore.service
sudo systemctl stop alsa-restore.service

# Drucker
sudo systemctl disable cups.service
sudo systemctl stop cups.service
sudo systemctl disable cups-browsed.service
sudo systemctl stop cups-browsed.service
sudo systemctl disable cups.path
sudo systemctl stop cups.path

# Create user if not exist
if ! id "$NEW_USER" &>/dev/null; then
    echo "→ Creating user $NEW_USER ..."
    useradd -m -s /bin/bash "$NEW_USER"
fi

# Add to sudo group
usermod -aG sudo "$NEW_USER"

# Passwordless sudo
echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/"$NEW_USER"
chmod 440 /etc/sudoers.d/"$NEW_USER"

### Configuring SSH Key Authentication ###
if [ -f "$SSH_KEY_FILE" ]; then
    echo "→ Installing SSH authorized key..."

    mkdir -p /home/pi/.ssh
    cat "$SSH_KEY_FILE" >> /home/pi/.ssh/authorized_keys
    chmod 700 /home/pi/.ssh
    chmod 600 /home/pi/.ssh/authorized_keys
    chown -R pi:pi /home/pi/.ssh

    # Optional: Passwortlogin deaktivieren
    # sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    # systemctl restart ssh

    echo "SSH key was installed successfully 🎉"
else
    echo "⚠️ No SSH key file found at $SSH_KEY_FILE — skipping"
fi

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8081/status.json")
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "Health check OK: HTTP $HTTP_STATUS"
else
    echo "Health check FAILED: HTTP $HTTP_STATUS"
    exit 1  # Skript abbrechen
fi

echo "###################################"
echo "Konfiguration abgeschlossen. Reboot wird in 10 Sekunden ausgeführt."
echo "###################################"
sleep 10
# UFW aktivieren
sudo ufw --force enable
sudo reboot