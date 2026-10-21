#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example, review DOMAIN before continuing."
fi

compose_files=(-f docker-compose.yml)

git pull --ff-only || true
sudo docker compose "${compose_files[@]}" build --pull
sudo docker compose "${compose_files[@]}" up -d --remove-orphans
sudo docker image prune -f
sudo docker compose "${compose_files[@]}" ps
