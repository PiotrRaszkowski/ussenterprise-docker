#!/usr/bin/env bash
set -euo pipefail

# Domyślne wartości
INTERVAL="${INTERVAL:-300}"      # co ile sekund odświeżać (domyślnie 5 min)
OVH_USER="${OVH_USER:?Musisz podać OVH_USER}"
OVH_PASSWORD="${OVH_PASSWORD:?Musisz podać OVH_PASSWORD}"

# Zbierz listę hostów:
# Priorytet:
# 1) Argumenty pozycyjne
# 2) HOSTNAMES (spacje rozdzielają)
# 3) HOSTNAME (pojedynczy, dla kompatybilności)
declare -a HOSTS=()

if (( $# > 0 )); then
    # Użyj argumentów skryptu jako hostów
    HOSTS=( "$@" )
elif [[ -n "${HOSTNAMES:-}" ]]; then
    # Rozdziel HOSTNAMES po spacjach
    # shellcheck disable=SC2206
    HOSTS=( ${HOSTNAMES} )
elif [[ -n "${HOSTNAME:-}" ]]; then
    HOSTS=( "${HOSTNAME}" )
else
    echo "Musisz podać hosty przez argumenty, zmienną HOSTNAMES lub HOSTNAME" >&2
    exit 1
fi

echo "Starting OVH Dynamic DNS updater"
echo "Interval: ${INTERVAL} s"
echo "Hostnames:"
for h in "${HOSTS[@]}"; do
    echo "  - ${h}"
done

while true; do
    # pobranie aktualnego IP (tutaj przez OpenDNS)
    IP="$(dig +short myip.opendns.com @resolver1.opendns.com || true)"
    if [[ -z "${IP}" ]]; then
        echo "$(date) › Nie udało się pobrać IP"
    else
        echo "$(date) › Aktualne IP: ${IP}"

        # Aktualizuj każdy host
        for HOST in "${HOSTS[@]}"; do
            # Pomijaj puste wpisy
            [[ -z "${HOST// }" ]] && continue

            # wywołanie OVH DynDNS API
            RESPONSE="$(curl -sS --fail -u "${OVH_USER}:${OVH_PASSWORD}" \
                "https://dns.eu.ovhapis.com/nic/update?system=dyndns&hostname=${HOST}&myip=${IP}" || true)"

            if [[ -n "${RESPONSE}" ]]; then
                echo "$(date) › [${HOST}] OVH response: ${RESPONSE}"
            else
                echo "$(date) › [${HOST}] OVH response: (brak odpowiedzi lub błąd)"
            fi
        done

        # wywołanie NextDNS (jeśli chcesz tylko raz, a nie per-host)
        if [[ -n "${NEXTDNS_LINK:-}" ]]; then
            RESPONSE="$(curl -sS --fail "${NEXTDNS_LINK}" || true)"
            echo "$(date) > NextDNS response: ${RESPONSE:-brak odpowiedzi lub błąd}"
        else
            # Zachowano oryginalny link; możesz go przenieść do zmiennej NEXTDNS_LINK
            RESPONSE="$(curl -s "https://link-ip.nextdns.io/ae661a/fd41ac377aece35f" || true)"
            echo "$(date) > NextDNS response: ${RESPONSE:-brak odpowiedzi lub błąd}"
        fi
    fi

    sleep "${INTERVAL}"
done

