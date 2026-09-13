#!/usr/bin/env bash
# Delete the provider service. Stop the LiteLLM / edge-proxy / tunnel terminals
# with Ctrl-C yourself. The schema is left in place (drop it manually if you want).
source "$(dirname "$0")/_common.sh"

databricks --profile "$DATABRICKS_PROFILE" \
  api delete "/api/2.1/unity-catalog/model-provider-services/$SERVICE_NAME" 2>&1 || true
echo "Deleted $SERVICE_NAME (if it existed)."
echo
echo "Optional — drop the demo schema:"
echo "  databricks --profile $DATABRICKS_PROFILE schemas delete ${CATALOG}.${SCHEMA}"
echo "Stop terminals 2/3/4 (LiteLLM, edge proxy, tunnel) with Ctrl-C."
