#!/usr/bin/env bash
# TERMINAL 1 (or one-shot): make sure Ollama is serving and both models are pulled.
# Ollama logs each /api/chat call in the terminal running `ollama serve`.
source "$(dirname "$0")/_common.sh"

command -v ollama >/dev/null || { echo "Install Ollama first: https://ollama.com"; exit 1; }
if ! curl -sf "${OLLAMA_HOST:-http://localhost:11434}/api/version" >/dev/null; then
  echo "Ollama is not responding at ${OLLAMA_HOST:-http://localhost:11434}."
  echo "Open a terminal and run:  ollama serve"
  exit 1
fi
echo "Pulling models (no-op if already present)…"
ollama pull qwen3.5:latest
ollama pull llama3.2:latest
echo "Ollama ready. Watch the 'ollama serve' terminal to see inference calls land."
