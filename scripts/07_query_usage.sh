#!/usr/bin/env bash
# ONE-SHOT: show what the gateway RECORDED for this service.
#   system.ai_gateway.usage           -> per-request tokens  (ingest lag ~20-25 min)
#   system.ai_gateway.external_model_spend -> USD cost (EMPTY for custom models)
source "$(dirname "$0")/_common.sh"
DBX=(databricks --profile "$DATABRICKS_PROFILE" experimental aitools tools query)

echo "=== system.ai_gateway.usage (tokens + request_tags, newest first) ==="
"${DBX[@]}" "SELECT event_time, destination_model, status_code, input_tokens, output_tokens, total_tokens, request_tags
FROM system.ai_gateway.usage
WHERE service_name='$SERVICE_NAME'
ORDER BY event_time DESC LIMIT 25"

echo
echo "=== request_tags breakdown (did team/project/environment — and cost? — land?) ==="
"${DBX[@]}" "SELECT request_tags['team'] AS team, request_tags['project'] AS project, request_tags['environment'] AS environment,
request_tags['cost'] AS cost, request_tags['cost_input'] AS cost_input, request_tags['cost_output'] AS cost_output,
count(*) AS calls, sum(total_tokens) AS tokens
FROM system.ai_gateway.usage
WHERE service_name='$SERVICE_NAME'
GROUP BY ALL ORDER BY calls DESC LIMIT 25"

echo
echo "=== per-model totals ==="
"${DBX[@]}" "SELECT destination_model, count(*) AS calls, sum(input_tokens) AS in_tok, sum(output_tokens) AS out_tok, sum(total_tokens) AS tot_tok
FROM system.ai_gateway.usage
WHERE service_name='$SERVICE_NAME' AND status_code=200
GROUP BY destination_model ORDER BY destination_model"

echo
echo "=== system.ai_gateway.external_model_spend (cost — expect EMPTY: custom model unpriced) ==="
"${DBX[@]}" "SELECT usage_start_time, usage_metadata.model AS model, usage_unit, usage_quantity
FROM system.ai_gateway.external_model_spend
WHERE usage_metadata.destination_name LIKE '%${SERVICE_ID}%'
ORDER BY usage_start_time DESC LIMIT 10"
