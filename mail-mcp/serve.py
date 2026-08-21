"""Uwierzytelniony front HTTP dla better-email-mcp.

better-email-mcp w trybie stdio nie ma auth (single-user, creds z env). Uruchamiamy
go jako backend po stdio, a przed nim stoi proxy FastMCP 3 z OAuth (realm mcpservers) —
ten sam wzorzec co sheets-mcp. Klient (Claude) uwierzytelnia się w Keycloaku; backend
dostaje EMAIL_CREDENTIALS i gada IMAP-em z Gmailem oraz iCloud.
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
        realm_url=_require("MAIL_MCP_AUTH_REALM_URL"),
        base_url=_require("MAIL_MCP_AUTH_BASE_URL"),
    )

    # Transport stdio przekazuje procesowi potomnemu tylko minimalny zestaw zmiennych,
    # wiec EMAIL_CREDENTIALS podajemy jawnie (ta sama pulapka co przy sheets-mcp).
    backend_env = {
        name: os.environ[name]
        for name in ("EMAIL_CREDENTIALS", "HOME", "PATH")
        if name in os.environ
    }

    proxy = create_proxy(
        {"mcpServers": {"mail": {"command": "better-email-mcp", "env": backend_env}}},
        name="Email",
        auth=auth,
    )

    proxy.run(transport="http", host="0.0.0.0", port=8000, path="/mcp")


if __name__ == "__main__":
    main()
