# gateway_link — LiteLLM behind the Unity AI Gateway

Register a **self-hosted LiteLLM proxy** (in front of local **Ollama**) as a
**custom Model Provider Service** in the **Unity AI Gateway**, then call it from
the Databricks control plane. The point of this folder is to **watch a single
request traverse the whole chain**, one terminal per hop, and to see exactly
which governance metadata Databricks records (and which it doesn't).

```
  Databricks control plane  (POST /ai-gateway/openai/v1/chat/completions)
        │   Databricks-Model-Provider-Service: <catalog>.<schema>.<service>
        ▼
  cloudflared quick tunnel   (public https://<...>.trycloudflare.com)
        ▼
  edge_proxy.py  :8899       ← TERMINAL 3: logs the request as it arrives from the
        │                       control plane (armeria UA, cf-connecting-ip, the
        │                       upstream key the gateway injected) + the LiteLLM
        │                       cost headers the gateway strips
        ▼
  LiteLLM  :4000             ← TERMINAL 2: logs tokens, cost, and provenance;
        │                       routes by the request `model` field
        ▼
  Ollama   :11434            ← TERMINAL 1: runs the actual inference
     (qwen3.5:latest, llama3.2:latest)
```

## What this proves (verified 2026-09-06, workspace `fevm-llm-misalignment`)

- ✅ LiteLLM registers as an `EXTERNAL_MODEL_PROVIDER_TYPE_CUSTOM` provider and is
  callable through `/ai-gateway`. The control plane really does reach a tunneled
  laptop.
- ✅ **One service, multiple models** — `qwen3.5` and `llama3.2` both flow through
  a single provider service; LiteLLM routes by the request `model` field.
- ✅ **Token metadata is recorded** by the gateway in `system.ai_gateway.usage`
  (`input_tokens` / `output_tokens` / `total_tokens`), matching LiteLLM's body
  `usage` exactly.
- ❌ **Cost is NOT recorded for a custom model.** `system.ai_gateway.external_model_spend`
  is priced from Databricks' own catalog keyed by `(provider, model)`; a custom
  model isn't in it, so no row. LiteLLM computes cost but returns it only in
  `x-litellm-response-cost*` **headers**, which the gateway strips. To govern cost
  for this pattern, keep it LiteLLM-side or emit it via app OTel spans
  (`mlflow.llm.cost`, as the sibling apps' `tracing.py` does).

## Key contract details (bit us during testing)

- **`base_url` is used verbatim as the POST target** — the gateway appends nothing.
  So it must be the full `…/v1/chat/completions`, *not* an OpenAI-SDK-style `…/v1`.
- **`base_url` is immutable via PATCH** → `05_register_provider.sh` deletes and
  recreates each run (the tunnel URL rotates anyway).
- **`allow_all_targets: true`** is what actually permits invocation.
- **Eventual consistency:** expect transient `403 model-not-allowed` then
  `404 Nodes do not exist` for a few seconds after (re)registration — the invoke
  script retries.
- **`system.ai_gateway.usage` lags ~20–25 min** — token rows aren't instant.

## Prerequisites

- [Ollama](https://ollama.com) running locally (`ollama serve`)
- `cloudflared` (`brew install cloudflared`) — quick tunnel, no account needed
- Databricks CLI authenticated to the target workspace
  (`databricks auth login --profile <profile>`)
- Python 3.11–3.13 (LiteLLM install); `uv` used if present

## Setup

```bash
cd gateway_link
cp .env.example .env          # edit profile / workspace / catalog / schema
chmod +x scripts/*.sh         # first time only
```

## Run it — four terminals + a request

| Terminal | Command | Shows |
| --- | --- | --- |
| 1 · Ollama | `ollama serve` (then `./scripts/01_setup_ollama.sh` once) | the actual model inference |
| 2 · LiteLLM | `./scripts/02_run_litellm.sh` | tokens, cost, provenance, Ollama call |
| 3 · Edge proxy | `./scripts/03_run_edge_proxy.sh` | control-plane request + stripped cost headers |
| 4 · Tunnel | `./scripts/04_run_tunnel.sh` | the public `trycloudflare.com` URL |

Then, in a fifth terminal:

```bash
./scripts/05_register_provider.sh          # reads the tunnel URL from logs/tunnel.log
./scripts/06_invoke_gateway.sh llama3.2     # fire from the control plane (fast model)
./scripts/06_invoke_gateway.sh qwen3.5 "Explain governance in one sentence."
./scripts/07_query_usage.sh                 # what the gateway recorded (~20min lag)
./scripts/99_cleanup.sh                     # delete the service when done
```

When you run step 6, watch terminals 3 → 2 → 1 light up in order: the edge proxy
logs the inbound gateway request, LiteLLM logs the token/cost breakdown and the
Ollama call, and Ollama logs the inference. The gateway response in terminal 5
carries token `usage` in the body but **no** `x-litellm-*` cost headers.

## Files

| File | Role |
| --- | --- |
| `litellm_config.yaml` | two Ollama models under one endpoint, with synthetic per-token prices |
| `logging_callback.py` | LiteLLM success logger (tokens/cost/provenance) |
| `edge_proxy.py` | logging reverse proxy between the tunnel and LiteLLM |
| `scripts/0*.sh` | one script per hop, plus register / invoke / query / cleanup |
| `.env` | profile, workspace, catalog/schema, LiteLLM key (gitignored) |

> This is a **demo/validation** harness, not production. The LiteLLM key is a
> local throwaway; the synthetic prices exist only to make cost visible. For a
> lasting setup use a UC service credential instead of a plaintext key and a
> stable tunnel/hostname instead of a rotating quick tunnel.
