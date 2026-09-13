#!/usr/bin/env bash
# ONE-SHOT: fire a request FROM the Databricks control plane through the gateway.
# Watch it traverse all four terminals: tunnel(edge) -> LiteLLM -> Ollama.
#
# Usage: ./06_invoke_gateway.sh [model] [prompt]
#   model  defaults to llama3.2 (fast, non-reasoning). Try qwen3.5 too.
source "$(dirname "$0")/_common.sh"

MODEL="${1:-llama3.2}"
PROMPT="${2:-Name three primary colours, comma separated.}"

TOKEN=$(databricks --profile "$DATABRICKS_PROFILE" auth token \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
URL="${WORKSPACE_HOST%/}/ai-gateway/openai/v1/chat/completions"

TAGS="${GATEWAY_REQUEST_TAGS:-}"
echo "POST $URL"
echo "  Databricks-Model-Provider-Service: $SERVICE_NAME"
echo "  Databricks-Ai-Gateway-Request-Tags: ${TAGS:-<none>}"
echo "  model=$MODEL"
for i in 1 2 3 4 5 6; do
  code=$(curl -s -m 120 -D "$LOGDIR/gw_headers.txt" -o "$LOGDIR/gw_body.json" -w "%{http_code}" \
    -X POST "$URL" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -H "Databricks-Model-Provider-Service: $SERVICE_NAME" \
    ${TAGS:+-H "Databricks-Ai-Gateway-Request-Tags: $TAGS"} \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}")
  [ "$code" = "200" ] && break
  echo "  attempt $i -> HTTP $code (propagation lag / slow model; retrying)"; sleep 6
done

echo "--- gateway response body (model answer + token usage) ---"
python3 -m json.tool < "$LOGDIR/gw_body.json" 2>/dev/null || cat "$LOGDIR/gw_body.json"
echo
echo "--- gateway response headers (NOTE: no x-litellm-* cost headers — gateway stripped them) ---"
grep -iE "^(x-databricks|x-litellm|server):" "$LOGDIR/gw_headers.txt" || echo "  (only databricks/server headers present)"
echo
echo "Tokens ride through in .usage; cost was dropped. Confirm capture with 07_query_usage.sh"
