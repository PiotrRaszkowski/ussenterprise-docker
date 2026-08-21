FROM python:3.12-slim

# fastmcp 3 zapewnia transport HTTP i OAuth (KeycloakAuthProvider); mcp-google-sheets
# jest backendem uruchamianym po stdio i sam auth nie ma.
#
# mcp<2 jest KONIECZNE: SDK mcp 2.0.0 usunal mcp.server.fastmcp, a mcp-google-sheets
# deklaruje mcp>=1.8.0 bez gornego ograniczenia — swieza instalacja bez pinu wywala sie
# na ImportError przy starcie.
RUN pip install --no-cache-dir \
      "fastmcp>=3.3.1,<4" \
      "mcp>=1.27,<2" \
      "mcp-google-sheets==0.6.3"

COPY serve.py /app/serve.py
WORKDIR /app

ENV PYTHONUNBUFFERED=1
CMD ["python", "/app/serve.py"]
