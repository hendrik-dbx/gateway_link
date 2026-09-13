#!/usr/bin/env bash
# TERMINAL 4: cloudflared quick tunnel exposing the edge proxy publicly.
# The https://<...>.trycloudflare.com URL is printed here AND saved to
# logs/tunnel.log, where 05_register_provider.sh reads it from.
source "$(dirname "$0")/_common.sh"

command -v cloudflared >/dev/null || {
  echo "cloudflared not installed. Install it:  brew install cloudflared"; exit 1; }

# --protocol http2 forces the edge connection over TCP/443 instead of the default
# QUIC (UDP/7844). Many corporate networks / VPNs drop egress UDP 7844, which makes
# the tunnel silently fail to connect (banner shows a URL, but Cloudflare returns
# 530 / error 1033). Override with TUNNEL_PROTOCOL=quic on an unrestricted network.
PROTO="${TUNNEL_PROTOCOL:-http2}"

echo "Starting cloudflared quick tunnel -> http://localhost:${EDGE_PORT} (protocol: $PROTO)"
echo "Copy the https://<...>.trycloudflare.com URL below (also saved to logs/tunnel.log)."
echo "Wait for a 'Registered tunnel connection' line before running 05 — the URL alone"
echo "does not mean it connected."
echo
cloudflared tunnel --protocol "$PROTO" --url "http://localhost:${EDGE_PORT}" 2>&1 | tee "$LOGDIR/tunnel.log"
