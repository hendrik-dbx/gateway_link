"""LiteLLM proxy success-logger.

Prints one clear block per request showing the token usage and cost the proxy
computed, WHERE each number comes from, and the local Ollama endpoint it
actually called. This is the "LiteLLM invocation" terminal in the demo.

Registered from litellm_config.yaml:
    litellm_settings:
      callbacks: logging_callback.proxy_handler_instance
"""

from datetime import datetime

from litellm.integrations.custom_logger import CustomLogger


def _usd(x):
    return f"${x:.8f}" if isinstance(x, (int, float)) else str(x)


class GatewayLogger(CustomLogger):
    def _emit(self, kwargs, response_obj, start_time, end_time):
        try:
            lp = kwargs.get("litellm_params", {}) or {}
            slo = kwargs.get("standard_logging_object", {}) or {}
            meta = lp.get("metadata", {}) or {}

            model_group = meta.get("model_group") or slo.get("model_group")
            underlying = kwargs.get("model") or slo.get("model")
            api_base = lp.get("api_base") or slo.get("api_base") or "?"

            usage = getattr(response_obj, "usage", None)
            pt = getattr(usage, "prompt_tokens", None) if usage else slo.get("prompt_tokens")
            ct = getattr(usage, "completion_tokens", None) if usage else slo.get("completion_tokens")
            tt = getattr(usage, "total_tokens", None) if usage else slo.get("total_tokens")

            total_cost = kwargs.get("response_cost")
            if total_cost is None:
                total_cost = slo.get("response_cost")
            in_ppt = lp.get("input_cost_per_token")
            out_ppt = lp.get("output_cost_per_token")
            input_cost = (pt or 0) * in_ppt if isinstance(in_ppt, (int, float)) and pt else None
            output_cost = (ct or 0) * out_ppt if isinstance(out_ppt, (int, float)) and ct else None

            try:
                dur = f"{(end_time - start_time).total_seconds():.2f}s"
            except Exception:
                dur = "?"

            print("\n" + "=" * 70)
            print(f"[LiteLLM] {datetime.now():%H:%M:%S}  request handled ({dur})")
            print(f"  requested model   : {model_group}")
            print(f"  -> routed to      : {underlying}")
            print(f"  -> OLLAMA (local) : {api_base}   <-- inference runs here")
            print("  --- tokens  (source: Ollama eval counts, surfaced in the OpenAI `usage` block) ---")
            print(f"      prompt_tokens     = {pt}")
            print(f"      completion_tokens = {ct}")
            print(f"      total_tokens      = {tt}")
            print("  --- cost  (source: computed by LiteLLM from configured *_cost_per_token) ---")
            print(f"      input_cost        = {_usd(input_cost)}")
            print(f"      output_cost       = {_usd(output_cost)}")
            print(f"      total_cost        = {_usd(total_cost)}")
            print("  NOTE: LiteLLM returns cost to callers ONLY via response headers")
            print("        (x-litellm-response-cost / -input / -output). The Databricks AI")
            print("        Gateway STRIPS these, so cost does NOT reach Databricks records.")
            print("        Tokens DO (system.ai_gateway.usage, from the body `usage`).")
            print("=" * 70, flush=True)
        except Exception as exc:  # never break the request path over logging
            print(f"[LiteLLM logger] error: {exc}", flush=True)

    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._emit(kwargs, response_obj, start_time, end_time)

    async def async_log_success_event(self, kwargs, response_obj, start_time, end_time):
        self._emit(kwargs, response_obj, start_time, end_time)

    async def async_post_call_success_hook(self, data, user_api_key_dict, response):
        """Inject LiteLLM's computed cost INTO the response body.

        By default LiteLLM returns cost only in x-litellm-* response HEADERS,
        which the Databricks AI Gateway strips. The gateway passes the response
        BODY through, so we stash the cost inside the `usage` block (and mirror
        it top-level) — that survives the gateway to reach the caller.
        (It still does NOT populate system.ai_gateway.* — those have fixed schemas.)
        """
        import litellm

        try:
            hp = getattr(response, "_hidden_params", None) or {}
            cost = hp.get("response_cost") if isinstance(hp, dict) else None
            if cost is None:
                cost = litellm.completion_cost(completion_response=response)
            cost = round(float(cost), 8)
            payload = {"total_cost_usd": cost, "currency": "USD", "source": "litellm"}

            usage = getattr(response, "usage", None)
            if usage is not None:
                try:
                    usage.cost = payload            # attribute style
                except Exception:
                    pass
                try:
                    usage["cost"] = payload         # dict style (belt and braces)
                except Exception:
                    pass
            try:
                response.litellm_cost = payload     # top-level mirror
            except Exception:
                pass
        except Exception as exc:
            print(f"[cost-in-body hook] {exc}", flush=True)
        return response


proxy_handler_instance = GatewayLogger()
