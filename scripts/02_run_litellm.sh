#!/usr/bin/env bash
# TERMINAL 2: LiteLLM proxy. First run creates .venv and installs litellm[proxy].
# Prints a per-request block (tokens, cost, provenance) via logging_callback.py.
source "$(dirname "$0")/_common.sh"

VENV="$ROOT/.venv"
if [ ! -x "$VENV/bin/litellm" ]; then
  echo "First run: creating venv + installing litellm[proxy]…"
  if command -v uv >/dev/null; then
    uv venv --python 3.13 "$VENV" 2>/dev/null || uv venv "$VENV"
    uv pip install --python "$VENV/bin/python" 'litellm[proxy]'
  else
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -U pip 'litellm[proxy]'
  fi
fi

cd "$ROOT"                              # so litellm can import logging_callback
export PYTHONPATH="$ROOT:${PYTHONPATH:-}"
echo "LiteLLM on :${LITELLM_PORT}  (models: qwen3.5, llama3.2 -> local Ollama)"
exec "$VENV/bin/litellm" --config "$ROOT/litellm_config.yaml" --port "${LITELLM_PORT}"
