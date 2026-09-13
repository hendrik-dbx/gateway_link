#!/usr/bin/env bash
# ONE-SHOT: register (or re-register) the LiteLLM proxy as a custom Unity AI
# Gateway model provider service. base_url must be the FULL chat-completions URL
# (the gateway posts to base_url verbatim), and base_url is immutable via PATCH,
# so we delete + recreate each run.
#
# Usage: ./05_register_provider.sh [TUNNEL_URL]
#   TUNNEL_URL defaults to the latest URL found in logs/tunnel.log.
source "$(dirname "$0")/_common.sh"

TUNNEL_URL="${1:-${TUNNEL_URL:-$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOGDIR/tunnel.log" 2>/dev/null | tail -1)}}"
[ -n "${TUNNEL_URL:-}" ] || { echo "No tunnel URL. Start 04_run_tunnel.sh, or pass the URL as an argument."; exit 1; }
BASE_URL="${TUNNEL_URL%/}/v1/chat/completions"

DBX=(databricks --profile "$DATABRICKS_PROFILE")
echo "Service  : $SERVICE_NAME"
echo "base_url : $BASE_URL"

"${DBX[@]}" schemas create "$SCHEMA" "$CATALOG" --comment "LiteLLM gateway_link demo" >/dev/null 2>&1 || true
"${DBX[@]}" api delete "/api/2.1/unity-catalog/model-provider-services/$SERVICE_NAME" >/dev/null 2>&1 || true

cat > "$LOGDIR/service_body.json" <<JSON
{
  "config": {
    "provider_type": "EXTERNAL_MODEL_PROVIDER_TYPE_CUSTOM",
    "custom": { "direct": {
      "base_url": "$BASE_URL",
      "api_key": { "plaintext": "$LITELLM_MASTER_KEY" }
    } },
    "allow_all_targets": true,
    "forward_unmanaged_paths": false,
    "targets": [
      { "model": "qwen3.5",  "native_api_types": ["openai/v1/chat/completions"] },
      { "model": "llama3.2", "native_api_types": ["openai/v1/chat/completions"] }
    ]
  },
  "comment": "LiteLLM -> local Ollama (gateway_link demo)"
}
JSON

"${DBX[@]}" api post \
  "/api/2.1/unity-catalog/model-provider-services?parent=${PARENT}&model_provider_service_id=${SERVICE_ID}" \
  --json "@$LOGDIR/service_body.json"
echo
echo "Registered. Propagation lag: first calls may 403/404 for a few seconds (06 retries)."
