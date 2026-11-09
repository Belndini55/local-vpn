#!/usr/bin/env bash
#
# setup-host-nat.sh — przygotowuje hosta do pełnego tunelu VPN (full tunnel).
#
# Uruchom raz na hoście serwera z uprawnieniami sudo:
#   sudo ./scripts/setup-host-nat.sh
#
# Skrypt:
#   1. Włącza forwardowanie IPv4 (net.ipv4.ip_forward=1)
#   2. Wykrywa interfejs z domyślną trasą (w stronę internetu)
#   3. Dodaje regułę MASQUERADE w iptables dla sieci VPN 10.13.13.0/24
#
# Dzięki temu klienci z AllowedIPs = 0.0.0.0/0, ::/0 będą mieli internet przez VPN.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Uruchom skrypt z sudo: sudo $0" >&2
    exit 1
fi

echo ">>> Włączam forwardowanie IPv4..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
# Trwałość po restarcie (Debian/Ubuntu)
if [ -f /etc/sysctl.conf ] && ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

echo ">>> Wykrywam interfejs z dostępem do internetu..."
OUT_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
if [ -z "$OUT_IFACE" ]; then
    echo "Błąd: nie wykryto interfejsu z domyślną trasą." >&2
    exit 1
fi
echo "Interfejs wyjściowy: $OUT_IFACE"

echo ">>> Dodaję regułę NAT (MASQUERADE) dla sieci VPN..."
iptables -t nat -C POSTROUTING -s 10.13.13.0/24 -o "$OUT_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.13.13.0/24 -o "$OUT_IFACE" -j MASQUERADE

iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i wg0 -j ACCEPT
iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -o wg0 -j ACCEPT

echo ">>> Gotowe. Ruch z sieci VPN (10.13.13.0/24) jest teraz maskowany przez $OUT_IFACE."
echo "Uwaga: reguły iptables nie przeżywają restartu — jeśli potrzebujesz trwałego NAT,"
echo "zainstaluj pakiet iptables-persistent i zapisz reguły (netfilter-persistent save)."
