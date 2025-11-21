#!/usr/bin/env bash
set -euo pipefail

API_KEY=""  # Trage hier deinen Ionos API-Key ein
BASE_URL="https://api.hosting.ionos.com/dns/v1"
TTL=3600
DOMAIN_ZONE=""
TARGET_DOMAINS=("")

# Aktuelle IPs
IP4=$(curl -s https://ipv4.icanhazip.com)
IP6=$(curl -s https://ipv6.icanhazip.com || echo "")

echo "▶ IPv4: $IP4"
echo "▶ IPv6: $IP6"

# Zone-ID holen
ZONE_ID=$(curl -s -H "X-API-Key: $API_KEY" "$BASE_URL/zones" |
  jq -r ".[] | select(.name==\"$DOMAIN_ZONE\") | .id")

if [[ -z "$ZONE_ID" ]]; then
  echo "❌ Zone $DOMAIN_ZONE nicht gefunden."
  exit 1
fi

# Zone + Records holen
ZONE_DATA=$(curl -s -H "X-API-Key: $API_KEY" "$BASE_URL/zones/$ZONE_ID?suffix=$DOMAIN_ZONE&recordType=A,AAAA")
RECORDS=$(echo "$ZONE_DATA" | jq -c '.records[]')

update_record() {
  local name="$1" type="$2" new_value="$3"

  [[ -z "$new_value" ]] && echo "⚠ Kein $type-Wert für $name – übersprungen" && return

  local existing
  existing=$(echo "$RECORDS" | jq -c "select(.name==\"$name\" and .type==\"$type\")")

  if [[ -n "$existing" ]]; then
    local current
    current=$(echo "$existing" | jq -r '.content')
    local id
    id=$(echo "$existing" | jq -r '.id')
    if [[ "$current" == "$new_value" ]]; then
      echo "✔ $name ($type) ist aktuell: $new_value"
    else
      echo "✏ Aktualisiere $name ($type): $current → $new_value"
      curl -s -X PUT "$BASE_URL/zones/$ZONE_ID/records/$id" \
        -H "Content-Type: application/json" -H "X-API-Key: $API_KEY" \
        -d "{\"content\":\"$new_value\",\"ttl\":$TTL,\"disabled\":false}" \
        > /dev/null && echo "  ✅ Aktualisiert"
    fi
  else
    echo "➕ Erstelle neuen $type-Record für $name: $new_value"
    curl -s -X POST "$BASE_URL/zones/$ZONE_ID/records" \
      -H "Content-Type: application/json" -H "X-API-Key: $API_KEY" \
      -d "[{\"name\":\"$name\",\"type\":\"$type\",\"content\":\"$new_value\",\"ttl\":$TTL,\"disabled\":false}]" \
      > /dev/null && echo "  ✅ Erstellt"
  fi
}

# Haupt-Loop
for domain in "${TARGET_DOMAINS[@]}"; do
  update_record "$domain" A "$IP4"
  update_record "$domain" AAAA "$IP6"
done

echo "✅ DNS-Update abgeschlossen"
echo $(date)