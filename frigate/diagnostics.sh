#!/bin/bash
## ===== DIAGNOSTYKA FRIGATE - RETENCJA =====

# 1. Nazwa kontenera Frigate (dostosuj jeśli inna)
FRIGATE_CONTAINER="frigate"

# 2. Sprawdź logi związane z retencją (ostatnie 24h)
echo "=== LOGI RETENCJI ==="
docker logs $FRIGATE_CONTAINER --since 24h 2>&1 | grep -iE "(retain|cleanup|delete|purge|recording)" | tail -50

# 3. Sprawdź błędy w logach
echo -e "\n=== BŁĘDY W LOGACH ==="
docker logs $FRIGATE_CONTAINER --since 24h 2>&1 | grep -iE "(error|exception|failed|errno)" | tail -30

# 4. Ścieżka do nagrań (dostosuj jeśli inna)
RECORDINGS_PATH="/mnt/frigate1/recordings"  # <-- ZMIEŃ NA SWOJĄ ŚCIEŻKĘ

# 5. Struktura katalogów - ile folderów dziennych istnieje
echo -e "\n=== FOLDERY DZIENNE (powinno być max 6-7) ==="
ls -la $RECORDINGS_PATH/ | head -20

# 6. Najstarsze pliki nagrań
echo -e "\n=== 10 NAJSTARSZYCH PLIKÓW ==="
find $RECORDINGS_PATH -name "*.mp4" -type f -printf '%T+ %p\n' 2>/dev/null | sort | head -10

# 7. Najnowsze pliki nagrań
echo -e "\n=== 10 NAJNOWSZYCH PLIKÓW ==="
find $RECORDINGS_PATH -name "*.mp4" -type f -printf '%T+ %p\n' 2>/dev/null | sort -r | head -10

# 8. Ile miejsca zajmuje każdy folder dzienny
echo -e "\n=== ROZMIAR FOLDERÓW DZIENNYCH ==="
du -sh $RECORDINGS_PATH/*/ 2>/dev/null | sort -h

# 9. Liczba plików .mp4 w systemie
echo -e "\n=== LICZBA PLIKÓW MP4 ==="
find $RECORDINGS_PATH -name "*.mp4" -type f | wc -l

# 10. Sprawdź bazę danych Frigate
echo -e "\n=== ROZMIAR BAZY DANYCH ==="
docker exec $FRIGATE_CONTAINER ls -lh /config/frigate.db 2>/dev/null || ls -lh /mnt/frigate/frigate.db 2>/dev/null

# 11. Stan dysku
echo -e "\n=== STAN DYSKU ==="
df -h $RECORDINGS_PATH

# 12. Sprawdź czy Frigate widzi właściwą ścieżkę
echo -e "\n=== MOUNT POINTS KONTENERA ==="
docker inspect $FRIGATE_CONTAINER --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'

# 13. Sprawdź uprawnienia do zapisu/usuwania
echo -e "\n=== TEST UPRAWNIEŃ ==="
touch $RECORDINGS_PATH/.test_write && rm $RECORDINGS_PATH/.test_write && echo "OK - zapis/usuwanie działa" || echo "BŁĄD - brak uprawnień"
