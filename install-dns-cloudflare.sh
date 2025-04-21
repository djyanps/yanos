#!/bin/bash

### CONFIGURATION À MODIFIER ###
DOMAIN="yanos.com"
DNS_IP="192.168.1.37"  # IP publique du serveur DNS
CF_API_TOKEN="8X542THQTmSkaUgJx_gLwU6fnAAd6tPIdW2s4aE5"
CF_ZONE_ID="f8bbbd00270d14255bfe303efdc3656f"
###############################

echo "[+] Installation de BIND9..."
apt update && apt install bind9 bind9utils bind9-doc curl jq -y

echo "[+] Configuration de la zone DNS..."
mkdir -p /etc/bind/zones

cat <<EOF >> /etc/bind/named.conf.local
zone "$DOMAIN" {
    type master;
    file "/etc/bind/zones/db.$DOMAIN";
};
EOF

cat <<EOF > /etc/bind/zones/db.$DOMAIN
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
@       IN      A       $DNS_IP
ns1     IN      A       $DNS_IP
www     IN      A       $DNS_IP
EOF

echo "[+] Vérification et redémarrage de BIND9..."
named-checkconf && named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN
systemctl restart bind9 && systemctl enable bind9

echo "[+] Exportation des enregistrements DNS vers Cloudflare..."

# Extraction des enregistrements depuis le fichier de zone
RECORDS=$(awk '/IN/ && !/SOA/ && !/NS/ { print $1, $4, $5 }' /etc/bind/zones/db.$DOMAIN)

while read -r name type value; do
    if [[ "$type" == "A" || "$type" == "CNAME" ]]; then
        echo "[*] Envoi de $name.$DOMAIN -> $value ($type)"

        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data '{
              "type": "'$type'",
              "name": "'$name.$DOMAIN'",
              "content": "'$value'",
              "ttl": 120,
              "proxied": false
            }' | jq '.success'
    fi
done <<< "$RECORDS"

echo "[✅] Installation terminée. Le DNS local est actif et les entrées sont envoyées à Cloudflare."
