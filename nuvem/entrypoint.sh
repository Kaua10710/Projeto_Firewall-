#!/bin/sh
# ---------------------------------------------------------------------------
# nuvem-supabase : rotas estaticas + nginx com TLS
# ---------------------------------------------------------------------------
set -e

/opt/kovenza/rotas.sh 172.28.30.254

echo "[nuvem-supabase] subindo nginx com TLS na porta 443"
exec /docker-entrypoint.sh "$@"
