"""Logging edge proxy — the "tunnel" terminal in the demo.

Sits between the cloudflared tunnel and LiteLLM:

    cloudflared -> edge_proxy(:EDGE_PORT) -> LiteLLM(:LITELLM_PORT)

Logs two things per call:
  (a) the request as it ARRIVES from the Databricks control plane through the
      tunnel — method, path, and the tell-tale headers: the `armeria` user-agent
      (Databricks serving infra), `cf-connecting-ip` (the control-plane egress IP,
      via Cloudflare), and the upstream `Authorization` the gateway injected.
  (b) the `x-litellm-*` cost/usage headers LiteLLM returns — they exist HERE but
      get stripped by the Databricks gateway before the caller ever sees them.

Plain stdlib, no deps. Non-streaming (buffered) — fine for the chat-completions demo.
"""

import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _cost_tags(headers: dict) -> dict:
    """Transpose LiteLLM's x-litellm-* cost headers into a string->string map
    suitable for a Databricks-Ai-Gateway-Request-Tags value. Values are stringified
    (Databricks request_tags is map<string,string>)."""
    tags = {}
    for k, v in headers.items():
        kl = k.lower()
        if kl.startswith("x-litellm-response-cost"):
            key = kl.replace("x-litellm-response-", "").replace("-", "_") or "cost"
            tags[key] = str(v)
        elif kl == "x-litellm-key-spend":
            tags["key_spend"] = str(v)
    if tags:
        tags["cost_source"] = "litellm"
    return tags

EDGE_PORT = int(os.environ.get("EDGE_PORT", "8899"))
LITELLM_PORT = int(os.environ.get("LITELLM_PORT", "4000"))
UPSTREAM = f"http://127.0.0.1:{LITELLM_PORT}"

REQ_HEADERS = (
    "authorization", "user-agent", "content-type", "host",
    "cf-connecting-ip", "cf-ray", "x-forwarded-for",
    "databricks-model-provider-service",
)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _read_body(self) -> bytes:
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def _log_request(self, body: bytes) -> None:
        print("\n" + "-" * 70)
        print(f"[EDGE] {time.strftime('%H:%M:%S')}  <- request arrived from the tunnel")
        print(f"  {self.command} {self.path}")
        for k in REQ_HEADERS:
            v = self.headers.get(k)
            if v is None:
                continue
            if k == "authorization":
                v = v[:14] + "…  (upstream LiteLLM key the gateway injected)"
            print(f"  {k}: {v}")
        if body:
            try:
                b = json.loads(body)
                print(f"  body.model        : {b.get('model')}")
                msgs = b.get("messages") or []
                if msgs:
                    print(f"  body.messages[-1] : {json.dumps(msgs[-1])[:200]}")
            except Exception:
                print(f"  body: {body[:200]!r}")
        print("-" * 70, flush=True)

    def _forward(self, body: bytes):
        req = urllib.request.Request(
            UPSTREAM + self.path,
            data=body or None,
            method=self.command,
            headers={
                k: v for k, v in self.headers.items()
                if k.lower() in ("authorization", "content-type", "accept")
            },
        )
        try:
            resp = urllib.request.urlopen(req, timeout=300)
            status, raw, headers = resp.status, resp.read(), dict(resp.getheaders())
        except urllib.error.HTTPError as e:
            status, raw, headers = e.code, e.read(), dict(e.headers)

        print(f"[EDGE] -> LiteLLM responded {status}")
        cost_hdrs = {
            k: v for k, v in headers.items()
            if k.lower().startswith("x-litellm") and any(
                t in k.lower() for t in ("cost", "spend", "model-name")
            )
        }
        if cost_hdrs:
            print("  LiteLLM cost headers seen here (the Databricks gateway STRIPS these):")
            for k, v in cost_hdrs.items():
                print(f"    {k}: {v}")
        print(flush=True)
        return status, raw, headers

    def _handle(self):
        body = self._read_body()
        self._log_request(body)
        status, raw, headers = self._forward(body)

        # EXPERIMENT: stamp the LiteLLM cost onto the RESPONSE as a
        # Databricks-Ai-Gateway-Request-Tags header, to test whether the gateway
        # will read request-tags off the upstream response (docs describe it as a
        # REQUEST-side header only). If it works, cost lands in
        # system.ai_gateway.usage.request_tags; if not, only the client's
        # request-side tags (team/project/environment) will.
        cost_tags = _cost_tags(headers)

        self.send_response(status)
        for k, v in headers.items():
            if k.lower() == "content-type" or k.lower().startswith("x-litellm"):
                self.send_header(k, v)
        if cost_tags:
            tag_json = json.dumps(cost_tags)
            self.send_header("Databricks-Ai-Gateway-Request-Tags", tag_json)
            print(f"[EDGE] stamped response-side Databricks-Ai-Gateway-Request-Tags: {tag_json}", flush=True)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    do_POST = _handle
    do_GET = _handle

    def log_message(self, *args):
        pass  # we print our own lines


if __name__ == "__main__":
    print(f"edge proxy listening on :{EDGE_PORT}  ->  LiteLLM {UPSTREAM}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", EDGE_PORT), Handler).serve_forever()
