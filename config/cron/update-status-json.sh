#!/bin/bash

LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
RAM=$(free | awk '/Mem:/ {printf("%.2f", $3/$2*100)}')
TEMP=$(vcgencmd measure_temp | grep -oP '[0-9.]+')

# SD-Karte (root filesystem)
USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

cat <<EOF > /var/www/status/status.json
{
  "load": "$LOAD",
  "ram": "$RAM",
  "temp": "$TEMP",
  "filesystem_usage": {
    "root": "$USAGE"
  }
}
EOF