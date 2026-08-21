"""Uwierzytelniony front HTTP dla mcp-google-sheets.

mcp-google-sheets stoi na FastMCP wbudowanym w SDK `mcp` i nie ma zadnego wsparcia dla
OAuth. Zamiast forkowac projekt, uruchamiamy go jako backend po stdio i wystawiamy przez
proxy FastMCP 3, ktore przejmuje uwierzytelnianie (ten sam realm Keycloaka co garmin-mcp).
"""

import os

from fastmcp.server import create_proxy
from fastmcp.server.auth.providers.keycloak import KeycloakAuthProvider


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Brak wymaganej zmiennej srodowiskowej: {name}")
    return value


def main() -> None:
    auth = KeycloakAuthProvider(
        realm_url=_require("SHEETS_MCP_AUTH_REALM_URL"),
        base_url=_require("SHEETS_MCP_AUTH_BASE_URL"),
    )

    # Backend NIE dziedziczy srodowiska: transport stdio przekazuje procesowi potomnemu
    # tylko minimalny bezpieczny zestaw zmiennych. Konfiguracje trzeba podac jawnie,
    # inaczej mcp-google-sheets nie zobaczy konta serwisowego ani filtra narzedzi
    # i wystartuje bez poswiadczen, z wszystkimi narzedziami wlaczonymi.
    backend_env = {
        name: os.environ[name]
        for name in ("SERVICE_ACCOUNT_PATH", "DRIVE_FOLDER_ID", "ENABLED_TOOLS", "HOME", "PATH")
        if name in os.environ
    }

    proxy = create_proxy(
        {
            "mcpServers": {
                "sheets": {"command": "mcp-google-sheets", "env": backend_env}
            }
        },
        name="Google Sheets",
        auth=auth,
    )

    proxy.run(
        transport="http",
        host="0.0.0.0",
        port=8000,
        path="/mcp",
    )


if __name__ == "__main__":
    main()
