#!/bin/bash
set -euxo pipefail
exec > /var/log/superset-bootstrap.log 2>&1

# Free instanca (t3.micro) ima samo 1GB RAM a Superset je memorijski zahtevan, pa dodajem swap fajl od 4GB
fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 1. Instalacija Dockera i Docker Compose plugina
dnf update -y
dnf install -y docker
systemctl enable --now docker

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

mkdir -p /opt/superset
cd /opt/superset

# 2. SQL skripta koja kreira zasebnu 'metrics' bazu za gold metrike
cat > /opt/superset/init-metrics.sql <<'SQL'
CREATE DATABASE metrics;
SQL

# 3. Superset konfiguracija (secret key + metadata baza)
cat > /opt/superset/superset_config.py <<'PYEOF'
import os
SECRET_KEY = "${superset_secret_key}"
SQLALCHEMY_DATABASE_URI = "postgresql+psycopg2://${db_user}:${db_password}@postgres:5432/superset"
SUPERSET_WEBSERVER_TIMEOUT = 120
PYEOF

# 4. Docker Compose definicija (Postgres + Superset)
cat > /opt/superset/docker-compose.yml <<'YAML'
services:
  postgres:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: "${db_user}"
      POSTGRES_PASSWORD: "${db_password}"
      POSTGRES_DB: superset
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-metrics.sql:/docker-entrypoint-initdb.d/init-metrics.sql:ro
    ports:
      # 5432 izložen na host-u da bi loader Lambda mogla da upiše metrike
      # (pristup je ograničen security grupom samo na Lambda SG)
      - "5432:5432"

  superset:
    image: apache/superset:3.1.0
    restart: always
    depends_on:
      - postgres
    environment:
      SUPERSET_SECRET_KEY: "${superset_secret_key}"
    ports:
      - "8088:8088"
    volumes:
      - ./superset_config.py:/app/pythonpath/superset_config.py:ro

volumes:
  pgdata:
YAML

# 5. Podizanje servisa
docker compose -f /opt/superset/docker-compose.yml up -d

# 6. Inicijalizacija Superseta (čeka da kontejner bude spreman)
for i in $(seq 1 30); do
  if docker compose -f /opt/superset/docker-compose.yml exec -T superset superset version; then
    break
  fi
  echo "Cekam da Superset kontejner postane spreman... ($i)"
  sleep 10
done

docker compose -f /opt/superset/docker-compose.yml exec -T superset superset db upgrade
docker compose -f /opt/superset/docker-compose.yml exec -T superset \
  superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname User \
  --email admin@admin.com \
  --password "${superset_admin_password}"
docker compose -f /opt/superset/docker-compose.yml exec -T superset superset init

echo "Superset bootstrap zavrsen."
