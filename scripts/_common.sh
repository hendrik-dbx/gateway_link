# Sourced by every script. Loads .env and derives names/paths.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # gateway_link/
ENV_FILE="$ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy .env.example to .env and edit it first." >&2
  exit 1
fi
set -a; . "$ENV_FILE"; set +a

: "${DATABRICKS_PROFILE:?set in .env}"
: "${WORKSPACE_HOST:?set in .env}"
: "${CATALOG:?}"; : "${SCHEMA:?}"; : "${SERVICE_ID:?}"
: "${LITELLM_MASTER_KEY:?}"; : "${LITELLM_PORT:?}"; : "${EDGE_PORT:?}"

LOGDIR="$ROOT/logs"; mkdir -p "$LOGDIR"
SERVICE_NAME="${CATALOG}.${SCHEMA}.${SERVICE_ID}"
PARENT="schemas/${CATALOG}.${SCHEMA}"
