# local-vpn

Lokalny VPN na bazie **WireGuard** uruchamiany przez **Docker Compose**.

WireGuard to nowoczesny, szybki i bezpieczny tunel VPN. Ten projekt pozwala postawić własny serwer VPN w swojej sieci (np. w domu lub na małym VPS) i łączyć się z komputera, telefonu lub tabletu.

## Struktura projektu

```
local-vpn/
├── docker-compose.yml        # definicja kontenera serwera WireGuard
├── wg0.conf.example          # przykładowa konfiguracja serwera (wzór)
├── .gitignore                # klucze i wygenerowane konfiguracje nie trafiają do gita
├── scripts/
│   ├── generate-client.sh    # generuje konfigurację nowego klienta (peera)
│   └── setup-host-nat.sh     # przygotowuje hosta (NAT, ip_forward) do pełnego tunelu
└── config/                   # tworzone automatycznie przy pierwszym uruchomieniu (klucze, peerzy)
```

## Wymagania

- Docker i Docker Compose na hoście, na którym ma działać serwer VPN
- Otwarty port **UDP 51820** w stronę serwera (firewall, router, ewentualnie grupy zabezpieczeń w chmurze)
- Uprawnienia `sudo` na hoście (do włączenia ip_forward i reguł iptables, jeśli chcesz kierować cały ruch przez VPN)

## Szybki start

1. Sklonuj repozytorium na maszynę, która ma być serwerem VPN:

   ```bash
   git clone <twoje-repo>/local-vpn.git
   cd local-vpn
   ```

2. Jeśli znasz zewnętrzny adres IP lub domenę serwera, ustaw ją w `docker-compose.yml` w zmiennej `SERVERURL` (można też zostawić `auto`, wtedy kontener spróbuje sam wykryć adres).

3. Uruchom serwer:

   ```bash
   docker compose up -d
   ```

4. Poczekaj chwilę, aż kontener wygeneruje klucze serwera i konfiguracje peerów. Sprawdź logi:

   ```bash
   docker compose logs -f
   ```

   Pliki konfiguracyjne klientów pojawią się w katalogu `config/peer1/`, `config/peer2/` itd.

5. Pobierz plik `config/peer1/peer1.conf` na urządzenie, z którego chcesz korzystać z VPN-a (np. przez `scp`, `sftp` lub otwórz i skopiuj zawartość).

6. Zainstaluj aplikację **WireGuard** na urządzeniu (Linux, Windows, macOS, Android, iOS), zaimportuj plik `.conf` i połącz.

## Dodawanie kolejnych urządzeń (peerów)

Uruchom skrypt generujący nowego klienta:

```bash
./scripts/generate-client.sh nazwa-urzadzenia
```

Skrypt:
- wygeneruje parę kluczy dla nowego klienta,
- doda jego klucz publiczny do konfiguracji serwera (i przeładuje WireGuard),
- wygotuje gotowy plik konfiguracyjny klienta w `config/<nazwa-urządzenia>/<nazwa-urządzenia>.conf`.

## Cały ruch przez VPN (full tunnel) vs tylko sieć VPN

Domyślnie klient kieruje przez VPN tylko ruch do sieci VPN (`10.13.13.0/24`). Jeśli chcesz, by **wszystko** (internet incluido) szło przez serwer:

1. W konfiguracji klienta ustaw:
   ```
   AllowedIPs = 0.0.0.0/0, ::/0
   ```
2. Na hoście serwera włącz przekazywanie pakietów i NAT (uruchom raz):

   ```bash
   sudo ./scripts/setup-host-nat.sh
   ```

   Skrypt włącza `net.ipv4.ip_forward=1` i dodaje regułę `MASQUERADE` dla interfejsu z internetem.

## Firewall na hoście (przykład ufw)

```bash
sudo ufw allow 51820/udp
```

## Rozwiązywanie problemów

- **Brak połączenia**: upewnij się, że port UDP 51820 jest otwarty i że `SERVERURL` w `docker-compose.yml` wskazuje na adres, pod którym klient widzi serwer (publiczne IP lub domena, nie `127.0.0.1`).
- **Połączony, ale brak internetu**: sprawdź, czy uruchomiłeś `scripts/setup-host-nat.sh` i czy w konfiguracji klienta masz `AllowedIPs = 0.0.0.0/0, ::/0`.
- **Klucze się nie generują**: kontener potrzebuje uprawnień `NET_ADMIN` — są one już dodane w `docker-compose.yml`.

## Bezpieczeństwo

Katalog `config/` zawiera prywatne klucze serwera i klientów — **nie commituj go do gita**. Plik `.gitignore` już to blokuje. Jeśli udostępniasz repozytorium publicznie, wygenerowane konfiguracje usuń przed wysłaniem commitów.

## Licencja

MIT — używaj na własną odpowiedzialność.