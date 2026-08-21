# garmin-mcp

Serwer MCP dający Claude dostęp do danych z Garmin Connect — aktywności, sen, HRV, VO2max,
training readiness — oraz możliwość **aktualizacji metadanych aktywności** (nazwa, typ, opis).
Wystawiony po HTTPS jako custom connector w claude.ai, działa bez udziału Maca.

- URL connectora: `https://garmin-mcp.lagowska46.ovh/mcp`
- Kontener: `garmin-mcp`, port 8000 wyłącznie w sieci `traefik-proxy` (nic nie jest publikowane na hosta)
- Narzędzi: 23 (22 z upstreamu + `update_activity`)

## Dlaczego fork, a nie oficjalny obraz

Stoimy na `github.com/PiotrRaszkowski/garmin-connect-mcp` (fork `eddmann/garmin-connect-mcp`),
branch `homelab`. Pięć różnic wobec upstreamu:

1. **Transport HTTP** — upstream serwuje tylko po stdio, czyli wymaga, żeby klient sam odpalił
   proces. Doszła flaga `--transport http`. Ten commit jest napisany pod PR do upstreamu.
2. **`update_activity`** — wszystkie narzędzia upstreamu dotyczące aktywności są tylko do odczytu.
   Nowe narzędzie ustawia nazwę, typ i opis. Garmin wymaga przy typie trójki
   `typeId`/`typeKey`/`parentTypeId`; narzędzie przyjmuje sam klucz (`trail_running`) i rozwiązuje
   resztę po stronie serwera, więc model nie zgaduje wewnętrznych ID.
3. **Praca na samych tokenach** — upstream odrzucał każde wywołanie narzędzia, jeśli nie było
   ustawionych `GARMIN_EMAIL` i `GARMIN_PASSWORD`, nawet gdy na dysku leżały ważne tokeny.
   `ConfigMiddleware` sprawdzał poświadczenia, zanim `init_garmin_client` zdążył sięgnąć po tokeny,
   które i tak preferuje. To blokowało dokładnie ten scenariusz, którego tu potrzebujemy — hasło
   nie może trafić na serwer. Ten commit też jest napisany pod PR.
4. **Opcjonalny OAuth** — `GARMIN_MCP_AUTH_PROVIDER=keycloak` włącza providera FastMCP.
   Domyślnie wyłączony, więc lokalne stdio działa jak wcześniej. Też pod PR.
5. **`garminconnect>=0.3.11`** — upstream ma `>=0.3.3`, a lock przypinał dokładnie 0.3.3.

## Jak zaktualizować obraz

Aktualizuje się, **gdy logowanie zacznie zwracać 401/403** — cała odporność na zmiany po stronie
Garmina (od marca 2026 weryfikują TLS fingerprint) siedzi w bibliotece `garminconnect`, która
wychodzi mniej więcej co tydzień.

```bash
cd /home/piotr/src/garmin-connect-mcp
git fetch upstream && git merge upstream/main      # albo rebase, jeśli wolisz
uv lock --upgrade-package garminconnect && uv sync
make can-release                                   # lint + pyright + testy
git tag -a homelab-RRRR-MM-DD -m "..." && git push origin homelab --tags
# aktualny tag: homelab-2026-08-19c
```

Potem w `docker-compose.yml` podmień ref w `build.context` i tag w `image:` na nowy, oraz:

```bash
cd /home/piotr/docker/garmin-mcp
docker compose build --no-cache && docker compose up -d
```

Obraz jest pinowany na tag i **nie ma etykiety watchtowera** — nie aktualizuje się sam.

## Tokeny — skąd się biorą

**Logowanie do Garmina NIGDY nie odbywa się na tym serwerze.** Kontener nie ma ustawionych
`GARMIN_EMAIL` ani `GARMIN_PASSWORD` i nie ma ich mieć. Powody:

- logowanie wymaga interaktywnego kodu MFA, którego w kontenerze nie ma jak podać,
- nieudane próby z nowego adresu ściągają challenge Cloudflare, a po kilku Garmin blokuje konto
  na 48–72 h,
- hasło do Garmina nie ma czego szukać na maszynie wystawionej do internetu.

Biblioteka najpierw próbuje wznowić sesję z katalogu tokenów, a dopiero gdy to zawiedzie, sięga po
hasło. Skoro hasła nie ma, druga ścieżka po prostu zwraca błąd — i o to chodzi. Nie ma też pętli
ponowień, więc wygasłe tokeny nie zamienią się w serię prób logowania.

### Procedura (powtarzasz ją, gdy token OAuth1 wygaśnie)

**1. Na Macu** — nie na serwerze:

```bash
uvx garmin-connect-mcp auth
```

Poda hasło i kod MFA. Powstaną: `~/.garminconnect/` (tokeny) oraz `~/.garminconnect.env` (hasło).

> Nie używaj do tego `ghcr.io/eddmann/garmin-connect-mcp:latest` — ten obraz ma w środku
> `garminconnect` 0.3.3 z maja i najpewniej odbije się od zabezpieczeń Garmina. `uvx` pobiera
> aktualną wersję.

**2. Przenieś na serwer wyłącznie katalog z tokenami.** Plik `.garminconnect.env` z hasłem
zostaje na Macu:

```bash
scp ~/.garminconnect/* piotr@192.168.10.30:/home/piotr/docker/garmin-mcp/tokens/
```

**3. Na serwerze** — uprawnienia i restart:

```bash
cd /home/piotr/docker/garmin-mcp
chmod 700 tokens && chmod 600 tokens/*
docker compose restart
```

Wolumen jest montowany do zapisu, bo biblioteka odświeża token OAuth2 w locie. Kontener chodzi
jako UID 1000, żeby odświeżone pliki zostały własnością `piotr` i kolejny `scp` nie wywalał się
na uprawnieniach.

## Bezpieczeństwo — trzy warstwy

Endpoint wystawia dane zdrowotne i potrafi modyfikować konto Garmin, więc chronią go trzy
niezależne warstwy. Każda z nich sama w sobie by nie wystarczyła.

**1. OAuth przez własnego Keycloaka** (`keycloak.lagowska46.ovh`, realm `mcpservers`).
Żądanie bez ważnego tokenu dostaje 401 z nagłówkiem `WWW-Authenticate` wskazującym metadane
zasobu. Claude rejestruje się sam przez Dynamic Client Registration — dlatego w connectorze
**nie podaje się client ID ani secretu**. Polityka `trusted-hosts` w realmie dopuszcza rejestrację
wyłącznie klientom deklarującym callback na `claude.ai`/`claude.com`; każdy inny dostaje 403.

**2. Allowlista IP** — middleware `anthropic-only@file` w Traefiku, zakres `160.79.104.0/21`.

**3. Sekret w ścieżce URL** — losowy segment w `.env` (`GARMIN_MCP_PATH_SECRET`).
Warstwa przejściowa z czasów sprzed OAuth. **Można ją zdjąć**, gdy OAuth potwierdzi się
w praktyce: usuń `PathPrefix` z reguły routera, ustaw `--path /mcp`, zaktualizuj URL w claude.ai.

### Dlaczego sama allowlista nie wystarczała

Zakres `160.79.104.0/21` to **współdzielona infrastruktura Anthropica**, nie adres przypisany do
konta. A nazwa hosta jest publiczna: Let's Encrypt zgłasza każdy certyfikat do logów Certificate
Transparency, więc `garmin-mcp.lagowska46.ovh` jest tam od chwili wystawienia. Każdy mógł ją
odczytać, dodać jako swój custom connector i trafić do nas z dozwolonej puli. Stąd warstwy 1 i 3.

### Znane zastrzeżenia

- **`manage_weight_data` potrafi kasować wpisy wagi, a deklaruje `destructiveHint: false`** — błąd
  w adnotacjach upstreamu. Klienci MCP używają tego hinta, żeby zdecydować, czy dopytać
  o potwierdzenie, więc skasowanie może przejść bez pytania. Nasze `update_activity` jest
  oznaczone uczciwie (`idempotentHint: true`).
- Świadomie **nie wystawiamy** `delete_activity` ani `create_manual_activity`, mimo że biblioteka
  je ma. Kasowanie aktywności jest nieodwracalne.
- Sekret ze ścieżki trafia do access logów Traefika (`docker logs traefik`). Kolejny powód, żeby
  warstwę 3 zdjąć, gdy przestanie być potrzebna.

## DNS

`garmin-mcp.lagowska46.ovh` jest w `HOSTNAMES` kontenera `lagowska46-ovh-dyndns`
(`/home/piotr/docker/dyndns/docker-compose.yml`) — OVH DynHost odświeża rekord A co 300 s na
aktualny adres łącza.

Sam wpis w `HOSTNAMES` nie wystarczy: **rekord DynHost musi wcześniej istnieć w panelu OVH**,
inaczej API odpowiada `404 {"class":"Client::NotFound","message":"No record found"}`.
Wewnątrz sieci nazwa działa bez żadnej konfiguracji, bo AdGuard ma wildcard
`*.lagowska46.ovh → 192.168.10.30`.

## Podpięcie w claude.ai

Customize → Connectors → „+" → Add custom connector, URL:

```
https://garmin-mcp.lagowska46.ovh/<GARMIN_MCP_PATH_SECRET>/mcp
```

Sekret weź z `.env`. **Pola OAuth Client ID i Client Secret zostaw puste** — Claude
rejestruje się w Keycloaku sam przez DCR. Przy pierwszym użyciu poprosi o zalogowanie
w realmie `mcpservers`.

**Zostaw bez OAuth** — pola client ID i client secret puste. Connector jest przypisany do konta,
więc jest dostępny wszędzie tam, gdzie logujesz się tym kontem.

## Diagnostyka

```bash
docker compose logs -f                    # logi serwera
docker compose ps                         # status + healthcheck

# Handshake z pominięciem Traefika (po sieci dockerowej):
docker run --rm --network traefik-proxy curlimages/curl -s -X POST \
  http://garmin-mcp:8000/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'

# Allowlista działa, jeśli TO ZWRACA 403 (jesteś spoza puli Anthropica):
curl -I https://garmin-mcp.lagowska46.ovh/mcp
```

Jeśli narzędzia zwracają 401/403 z Garmina — tokeny wygasły. Wracasz do procedury wyżej,
**z Maca**. Nie próbuj ratować sytuacji logowaniem z serwera i nie ponawiaj prób w pętli.
