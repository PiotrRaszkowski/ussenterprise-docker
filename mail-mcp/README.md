# mail-mcp

Czytanie poczty (Gmail + iCloud) przez IMAP, z załącznikami. Serwer MCP za HTTPS jako custom
connector w claude.ai.

- URL connectora: `https://mail-mcp.lagowska46.ovh/mcp`
- Kontener: `mail-mcp`, port 8000 wyłącznie w sieci `traefik-proxy` (bez portu na hoście)
- Konta: Gmail + iCloud, oba przez IMAP

## Dlaczego self-host, skoro jest oficjalny Gmail connector

Oficjalny connector Anthropica zwraca metadane załączników (`{id, mimeType, filename}`), ale
**nie pobiera zawartości** — na liście jego 27 narzędzi nie ma `get_attachment`. Do autonomicznego
czytania PDF-a z maila trzeba self-hostu. Ten serwer zwraca `content_base64` inline, więc Claude
realnie przeczyta plik — z obu kont jednym interfejsem.

## Architektura: proxy przed nieuwierzytelnionym backendem

Backend `@n24q02m/better-email-mcp` (Node, stdio) nie ma własnego auth. Stoi za proxy FastMCP 3
(Python), które dokłada OAuth przez Keycloaka — ten sam wzorzec co sheets-mcp. Obraz jest
dwuruntime'owy (Node 24 + Python).

```
Claude → HTTPS → Traefik (allowlista IP) → proxy FastMCP 3 (OAuth/Keycloak) → stdio → better-email-mcp → IMAP
```

## Dostęp do skrzynek

App-specific passwords (NIE zwykłe hasła), w `EMAIL_CREDENTIALS` (`.env`, gitignored, 600).
Format: `adres:hasło`, konta po przecinku.

- **Gmail:** włącz IMAP w ustawieniach + wygeneruj App Password (wymaga 2FA Google). App Password
  wpisz **bez spacji**. `imap.gmail.com:993`.
- **iCloud:** 2FA na Apple ID + app-specific password (`appleid.apple.com`), z myślnikami.
  `imap.mail.me.com:993`.

## Bezpieczeństwo

Dwie warstwy: OAuth (realm `mcpservers`, serwer sam zwraca 401 bez tokenu) + allowlista IP
`anthropic-only@file`. Sama allowlista nie wystarcza — zakres Anthropica jest współdzielony,
a nazwa hosta jest publiczna w logach Certificate Transparency.

**Nie read-only** (świadoma decyzja) — serwer ma też wysyłanie i kasowanie. App-specific password
sam w sobie daje pełny dostęp IMAP do skrzynki.

**Ryzyko łańcucha mail→zapis.** Treść maila (od kogokolwiek) wraca do modelu. W jednej rozmowie
z connectorem mającym zapis (np. baselinker-mcp) złośliwy mail może teoretycznie pociągnąć akcję
gdzie indziej. Nie trzymać czytania poczty i zapisujących connectorów w jednej autonomicznej
rozmowie.

## Aktualizacja

Podbij wersję `@n24q02m/better-email-mcp` w `Dockerfile`, potem
`docker compose build --no-cache && docker compose up -d`. Obraz pinowany, bez watchtowera.

## Diagnostyka

```bash
docker compose logs -f

# Allowlista działa, jeśli TO zwraca 403 (spoza puli Anthropica):
curl -I https://mail-mcp.lagowska46.ovh/mcp
```
