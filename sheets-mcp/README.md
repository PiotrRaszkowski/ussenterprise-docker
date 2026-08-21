# sheets-mcp

Dostęp Claude do Arkuszy Google. Serwer MCP wystawiony po HTTPS jako custom connector,
działa bez udziału przeglądarki i bez tokenów wygasających w tle.

- URL connectora: `https://sheets-mcp.lagowska46.ovh/mcp`
- Kontener: `sheets-mcp`, port 8000 wyłącznie w sieci `traefik-proxy`
- Narzędzi: 19 (20 z upstreamu minus `share_spreadsheet`)

## Dlaczego nie oficjalny serwer Google

Google ma własny, hostowany serwer MCP (`https://sheetsmcp.googleapis.com/mcp/v1`) i był
pierwszym wyborem — zero infrastruktury po naszej stronie. **Nie zadziałał.**

Konfiguracja przeszła w całości: API włączone, klient OAuth utworzony, zgoda udzielona, token
wydany. Mimo to każde wywołanie narzędzia wracało z `PERMISSION_DENIED`. Przyczyna leży poza
naszym zasięgiem: usługi `*mcp.googleapis.com` są bramkowane przez **Workspace MCP Developer
Preview**, a program wymaga konta Google Workspace, zapisu przez formularz i dodania do grupy.
Konto `@gmail.com` się nie kwalifikuje. Diagnostyka:

```bash
gcloud services list --enabled --project=mcp-servers-506018 | grep -i mcp
# sheetsmcp.googleapis.com JEST włączone, a wywołania i tak wracają 403 → allowlista preview
```

Gdyby Google otworzyło preview szerzej, warto rozważyć powrót — ich serwer ma tylko 6 narzędzi,
ale zero utrzymania. Nasz ma 19, w tym wyszukiwanie i listowanie arkuszy, których tamten nie ma.

## Architektura: proxy przed nieuwierzytelnionym backendem

`xing5/mcp-google-sheets` stoi na FastMCP **wbudowanym w SDK `mcp`**, nie na samodzielnym
FastMCP 3 — nie ma więc `KeycloakAuthProvider` ani żadnego wsparcia dla OAuth. Zamiast forkować
projekt, uruchamiamy go jako backend po stdio, a przed nim stoi cienki serwer FastMCP 3
(`serve.py`), który przejmuje uwierzytelnianie:

```
Claude → HTTPS → Traefik (allowlista IP) → proxy FastMCP 3 (OAuth/Keycloak) → stdio → mcp-google-sheets → Google API
```

Zysk: backend zostaje nietknięty i aktualizuje się przez zwykłe podbicie wersji w `Dockerfile`,
a auth jest ten sam co w [garmin-mcp](../garmin-mcp/README.md) — realm `mcpservers`, DCR, więc
w connectorze pola client ID i secret zostają **puste**.

### Dwie pułapki, na które trafiliśmy

**1. `mcp<2` jest obowiązkowe.** SDK `mcp` 2.0.0 usunął `mcp.server.fastmcp`, a
`mcp-google-sheets` deklaruje `mcp>=1.8.0` bez górnego ograniczenia. Bez pinu obraz nie wstaje:
`ModuleNotFoundError: No module named 'mcp.server.fastmcp'`.

**2. Backend nie dziedziczy środowiska.** Transport stdio przekazuje procesowi potomnemu tylko
minimalny bezpieczny zestaw zmiennych. `SERVICE_ACCOUNT_PATH`, `DRIVE_FOLDER_ID` i `ENABLED_TOOLS`
trzeba podać jawnie w `serve.py` — inaczej backend startuje bez poświadczeń (próbuje OAuth, potem
ADC, w końcu się wywraca) i bez filtra narzędzi. Objawem w Claude jest
„This connector has no tools available", a nie błąd.

## Dostęp do Google: konto serwisowe

`sheets-mcp@mcp-servers-506018.iam.gserviceaccount.com`, klucz w `service-account.json`
(gitignored, 600). Konto **nie ma żadnych ról projektowych** — widzi wyłącznie to, co
udostępnisz mu na Dysku Google.

Żeby dodać arkusz: otwórz go → Udostępnij → wpisz adres konta serwisowego, rola **Przeglądający**
(odczyt) lub **Edytor** (zapis), odznacz „Powiadom osoby" (konto nie ma skrzynki).

Działa też dla plików, których nie jesteś właścicielem — o ile masz prawo udostępniania.
**Skrót do Dysku nie wystarczy**: konto zobaczy skrót, ale nie otworzy pliku docelowego.

`DRIVE_FOLDER_ID` jest **pusty** i to jest świadome. Ta zmienna filtruje wyłącznie
`list_spreadsheets`, `list_folders` i `create_spreadsheet` — nie jest granicą uprawnień.
Pusta oznacza, że listowanie pokazuje wszystko, co udostępnione kontu. Granicę trzyma lista
udostępnień, nie folder.

## Bezpieczeństwo

Dwie warstwy, obie niezbędne:

1. **OAuth przez Keycloaka** (realm `mcpservers`) — bez tokenu serwer zwraca 401.
2. **Allowlista IP** `anthropic-only@file` w Traefiku — zakres `160.79.104.0/21`.

Sama allowlista nie wystarcza: zakres jest współdzielony przez całą infrastrukturę Anthropica,
a nazwa hosta trafia do publicznych logów Certificate Transparency w chwili wystawienia
certyfikatu. W ciągu kilkunastu minut od wystawienia w logach pojawiły się skanery z sześciu
różnych adresów — wszystkie odbite przez allowlistę.

`share_spreadsheet` jest **wyłączone** przez `ENABLED_TOOLS` — to jedyne narzędzie, które potrafi
wypuścić dane poza konto serwisowe, nadając uprawnienia dowolnemu adresowi e-mail.

## Aktualizacja

```bash
cd /home/piotr/docker/sheets-mcp
# podbij wersje w Dockerfile (mcp-google-sheets), zachowując pin mcp<2
docker compose build --no-cache && docker compose up -d
```

Obraz jest pinowany na tag i **nie ma etykiety watchtowera**.

## Diagnostyka

```bash
docker compose logs -f

# Czy backend widzi arkusze (omija proxy i OAuth, testuje samo Google):
docker run --rm --network traefik-proxy \
  -v $PWD/service-account.json:/creds/sa.json:ro \
  --entrypoint python sheets-mcp:2026-08-19 -c "
from google.oauth2 import service_account
from googleapiclient.discovery import build
c=service_account.Credentials.from_service_account_file('/creds/sa.json',
    scopes=['https://www.googleapis.com/auth/spreadsheets','https://www.googleapis.com/auth/drive'])
for f in build('drive','v3',credentials=c).files().list(
    q=\"mimeType='application/vnd.google-apps.spreadsheet'\", fields='files(id,name)').execute()['files']:
    print(f['id'], f['name'])"

# Allowlista działa, jeśli TO zwraca 403:
curl -I https://sheets-mcp.lagowska46.ovh/mcp
```

Jeśli connector zgłasza brak narzędzi — patrz na logi kontenera, nie na Claude. Backend spawnuje
się dopiero przy pierwszej sesji klienta, więc sam start kontenera niczego nie dowodzi.
