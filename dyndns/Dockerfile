FROM alpine:latest

# Zainstaluj curl i narzędzia DNS
RUN apk add --no-cache curl bind-tools bash

# Skopiuj skrypt i ustaw jako entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
