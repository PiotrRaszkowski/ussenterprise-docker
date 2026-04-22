#!/bin/bash
docker stop frigate

# Usuń bazę danych
sudo rm -f /home/piotr/docker/frigate/config/frigate.db
sudo rm -f /home/piotr/docker/frigate/config/frigate.db-shm
sudo rm -f /home/piotr/docker/frigate/config/frigate.db-wal

# Usuń wszystkie nagrania
sudo rm -rf /mnt/frigate1/recordings/*

# Usuń clipy/snapshoty (opcjonalnie, ale dla pełnej czystości)
sudo rm -rf /mnt/frigate1/clips/*
sudo rm -rf /mnt/frigate1/exports/*

# Sprawdź czy czysto
ls -la /mnt/frigate1/
df -h /mnt/frigate1

# Uruchom Frigate
docker start frigate

# Sprawdź logi
sleep 30
docker logs frigate 2>&1 | tail -30
