# Dwa runtime w jednym obrazie:
#  - backend: @n24q02m/better-email-mcp (Node, stdio) — mówi IMAP do Gmaila i iCloud
#  - front:   proxy FastMCP 3 (Python) — dokłada OAuth (Keycloak, realm mcpservers)
# Wzorzec identyczny jak sheets-mcp: serwer bez własnego auth stoi za uwierzytelniającym proxy.
FROM node:24-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Backend pinowany — nie ciągniemy latest przy starcie (offline, powtarzalnie).
RUN npm install -g @n24q02m/better-email-mcp@1.39.0

# mcp<2 na wszelki wypadek spójności z resztą; fastmcp 3 daje HTTP + KeycloakAuthProvider.
RUN python3 -m venv /venv \
    && /venv/bin/pip install --no-cache-dir "fastmcp>=3.3.1,<4" "mcp>=1.27,<2"

COPY serve.py /app/serve.py
WORKDIR /app
ENV PYTHONUNBUFFERED=1
CMD ["/venv/bin/python", "/app/serve.py"]
