#!/usr/bin/env bash
set -e

# Store the initial script directory
ORIGINAL_DIR="$(pwd)"

SERVICES=(
  "../movie-service"
  "../user-account-service"
  "../recommendation-service"
)

# 1. Build all services using their respective Maven Wrappers
for SERVICE in "${SERVICES[@]}"; do
  echo "=========================================="
  echo "Building $SERVICE"
  echo "=========================================="

  cd "$SERVICE"
  chmod +x mvnw
  ./mvnw clean package

  # Return to the starting directory
  cd "$ORIGINAL_DIR"
done

# 2. Build and start Docker containers
echo "=========================================="
echo "Building Docker Images"
echo "=========================================="
docker compose build

echo "=========================================="
echo "Starting Containers"
echo "=========================================="
docker compose up