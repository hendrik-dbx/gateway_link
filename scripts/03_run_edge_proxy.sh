#!/usr/bin/env bash
# TERMINAL 3: logging edge proxy. Logs the request as it arrives from the tunnel
# (control-plane headers) and the LiteLLM cost headers that the gateway strips.
source "$(dirname "$0")/_common.sh"
export EDGE_PORT LITELLM_PORT
echo "Edge proxy on :${EDGE_PORT}  ->  LiteLLM :${LITELLM_PORT}"
exec python3 "$ROOT/edge_proxy.py"
