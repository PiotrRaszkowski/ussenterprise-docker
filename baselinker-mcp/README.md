# baselinker-mcp — wdrozenie na ussenterprise

Serwer MCP dajacy Claude dostep do BaseLinkera: zamowienia, faktury, zwroty, kurierzy, CRM,
magazyny, produkty, dokumenty, Base Connect i magazyny zewnetrzne. Wystawiony po HTTPS jako
custom connector w claude.ai.

- URL connectora: `https://baselinker-mcp.lagowska46.ovh/mcp`
- Kontener: `baselinker-mcp`, port 8000 wylacznie w sieci `traefik-proxy` (nic nie jest publikowane na hosta)
- Narzedzi: 10 (kategorie API BaseLinkera), za nimi 179 metod — 87 odczytu + 92 zapisu

## Instalacja

```bash
mkdir -p /home/piotr/docker/baselinker-mcp && cd /home/piotr/docker/baselinker-mcp
# skopiuj tu docker-compose.yml, .env.example i ten README z repo (katalog deploy/)
cp .env.example .env    # i wklej token BaseLinkera
chmod 600 .env
docker compose build && docker compose up -d
```

Obraz jest budowany wprost z gita, pinowany na tag (`#v0.2.0`) i **nie ma etykiety watchtowera** —
nie aktualizuje sie sam. Aktualizacja: nowy tag w repo, podmiana refa w `build.context` i tagu
w `image:`, potem `docker compose build --no-cache && docker compose up -d`.

## DNS — trzeba zrobic recznie przed pierwszym startem

1. **W panelu OVH** zaloz rekord DynHost `baselinker-mcp.lagowska46.ovh`. Bez tego API DynHost
   odpowiada `404 {"class":"Client::NotFound","message":"No record found"}`.
2. Dopisz `baselinker-mcp.lagowska46.ovh` do `HOSTNAMES` w
   `/home/piotr/docker/dyndns/docker-compose.yml` i `docker compose up -d` w tym katalogu.

Wewnatrz sieci nazwa dziala od razu — AdGuard ma wildcard `*.lagowska46.ovh → 192.168.10.30`.

## Bezpieczenstwo — trzy warstwy

Endpoint ma **wlaczone zapisy** (`BASELINKER_ALLOW_WRITES=true`): potrafi zmieniac zamowienia,
stany magazynowe, ceny, faktury i nadawac realne przesylki kurierskie. To jest promien razenia.

**1. OAuth przez wlasnego Keycloaka** (`keycloak.lagowska46.ovh`, realm `mcpservers`) — ten sam
co garmin-mcp i sheets-mcp. Zadanie bez waznego tokenu dostaje 401 z naglowkiem
`WWW-Authenticate` wskazujacym metadane zasobu. Serwer sam weryfikuje podpis JWT po JWKS realmu,
sprawdza `iss` i wymaga scope `openid`. Claude rejestruje sie przez Dynamic Client Registration —
w connectorze **nie podaje sie client ID ani secretu**. Polityka `trusted-hosts` w realmie
dopuszcza rejestracje wylacznie klientom deklarujacym callback na `claude.ai`/`claude.com`.

**2. Allowlista IP** — middleware `anthropic-only@file` w Traefiku, zakres `160.79.104.0/21`.
Sama nie wystarcza: to wspoldzielona infrastruktura Anthropica, a nazwa hosta jest publiczna
w logach Certificate Transparency od chwili wystawienia certyfikatu.

**3. Kontener** — `read_only`, `no-new-privileges`, UID 1000, bez `ports:`, `/tmp` na tmpfs.

### Znane zastrzezenia

- **Token BaseLinkera jest wspolny.** Kazdy uzytkownik realmu `mcpservers` dziala na tym samym
  koncie BaseLinker. Czlonkostwo w realmie = pelny dostep do konta.
- Zapisy sa wlaczone hurtem, bez podzialu na role. Jesli ma byc inaczej, najprostsza droga to
  drugi kontener z `BASELINKER_ALLOW_WRITES` nieustawionym pod osobnym hostem.
- `save_to_path` (zapis pliku na dysk) jest po HTTP odrzucany — pisalby na dysk serwera, nie
  klienta. Etykiety i faktury wracaja jako embedded resource.

## Podpiecie w claude.ai

Settings → Connectors → „+" → Add custom connector, URL:

```
https://baselinker-mcp.lagowska46.ovh/mcp
```

**Pola OAuth Client ID i Client Secret zostaw puste.** Przy pierwszym uzyciu Claude poprosi
o zalogowanie w realmie `mcpservers`.

## Diagnostyka

```bash
docker compose logs -f
docker compose ps                         # status + healthcheck

# Healthcheck i metadane OAuth (po sieci dockerowej, z pominieciem Traefika):
docker run --rm --network traefik-proxy curlimages/curl -s http://baselinker-mcp:8000/healthz
docker run --rm --network traefik-proxy curlimages/curl -s \
  http://baselinker-mcp:8000/.well-known/oauth-protected-resource/mcp

# Powinno zwrocic 401 z naglowkiem WWW-Authenticate:
docker run --rm --network traefik-proxy curlimages/curl -si -X POST \
  http://baselinker-mcp:8000/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'

# Allowlista dziala, jesli TO ZWRACA 403 (jestes spoza puli Anthropica):
curl -I https://baselinker-mcp.lagowska46.ovh/mcp
```

`401 invalid_token` z opisem `no applicable key found in the JSON Web Key Set` oznacza token
podpisany kluczem spoza realmu. `401` z `unexpected "iss" claim value` — token z innego realmu.
