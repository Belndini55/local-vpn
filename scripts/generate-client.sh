#!/usr/bin/env bash
#
# generate-client.sh — generuje nowego klienta (peera) WireGuard i dopisuje go do serwera.
#
# Użycie: ./scripts/generate-client.sh <nazwa-urządzenia>
# Przykład: ./scripts/generate-client.sh laptop-domowy
#
# Wymagania: docker compose, wireguard-tools (wget do pobierania confa z kontenera)

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Użycie: $0 <nazwa-urządzenia>"
    echo "Przykład: $0 telefon"
    exit 1
fi

CLIENT_NAME="$1"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$COMPOSE_DIR/config"
CLIENT_DIR="$CONFIG_DIR/$CLIENT_NAME"

if ! command -v docker >/dev/null 2>&1; then
    echo "Błąd: docker nie jest zainstalowany." >&2
    exit 1
fi

if ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --services 2>/dev/null | grep -q wireguard; then
    echo "Błąd: nie wykryto usługi wireguard w docker-compose.yml." >&2
    exit 1
fi

mkdir -p "$CLIENT_DIR"

echo ">>> Generuję klucze dla klienta: $CLIENT_NAME"

# Wygeneruj parę kluczy klienta (w kontenerze, żeby użyć wg-tools zainstalowanych tam)
CLIENT_KEYS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T wireguard bash -c '
    umask 077
    CLIENT_PRIV=$(wg genkey)
    CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
    echo "$CLIENT_PRIV|$CLIENT_PUB"
')

CLIENT_PRIV=$(echo "$CLIENT_KEYS" | cut -d'|' -f1)
CLIENT_PUB=$(echo "$CLIENT_KEYS" | cut -d'|' -f2)

# Znajdź kolejny wolny adres IP w puli 10.13.13.0/24
EXISTING_IPS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T wireguard bash -c '
    grep -oP "AllowedIPs = 10\.13\.13\.\K[0-9]+" /config/wg0.conf 2>/dev/null || true
' | sort -n | tail -n1 || echo "1")

NEXT_IP=$((EXISTING_IPS + 1))
if [ "$NEXT_IP" -lt 2 ]; then
    NEXT_IP=2
fi
CLIENT_IP="10.13.13.$NEXT_IP/32"

# Pobierz publiczny klucz serwera
SERVER_PUB=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T wireguard bash -c '
    grep "PublicKey" /config/peer1/peer1.conf 2>/dev/null | awk "{print \$3}" || true
')
if [ -z "$SERVER_PUB" ]; then
    # Fallback: wyciągnij z wg0.conf (server private key -> nie ma publicznego, więc szukamy w peerach)
    SERVER_PUB=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T wireguard bash -c '
        head -n 1 /config/peer1/peer1.conf 2>/dev/null | grep -oP "PublicKey = \K.*" || true
    ')
fi

echo ">>> Przypisany adres klienta: $CLIENT_IP"

# Dopisz peer-a do konfiguracji serwera i przeładuj WireGuard
docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T wireguard bash -c "
    umask 077
    cat >> /config/wg0.conf <<PEER

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUB
AllowedIPs = $CLIENT_IP
PEER
    wg syncconf wg0 <(wg-quick strip wg0)
"

# Wygeneruj gotowy plik konfiguracyjny klienta
cat > "$CLIENT_DIR/$CLIENT_NAME.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP
DNS = 1.1.1.1

[Peer]
# Serwer WireGuard (lokalny VPN)
PublicKey = $SERVER_PUB
Endpoint = SERVER_URL_OR_IP:51820
AllowedIPs = 10.13.13.0/24
# Ustaw poniżej 0.0.0.0/0, ::/0 jeśli cały ruch ma iść przez VPN (full tunnel)
PersistentKeepalive = 25
EOF

echo ">>> Gotowe!"
echo "Plik konfiguracyjny klienta: $CLIENT_DIR/$CLIENT_NAME.conf"
echo ""
echo "WAŻNE: W pliku klienta zmień 'SERVER_URL_OR_IP:51820' na rzeczywisty adres serwera VPN."
echo "Jeśli chcesz kierować cały ruch przez VPN, zmień AllowedIPs na: 0.0.0.0/0, ::/0"
echo ""
echo "Na hoście serwera (dla full tunnel) raz uruchom: sudo ./scripts/setup-host-nat.sh"
