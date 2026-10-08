#!/bin/sh
# ---------------------------------------------------------------------------
# edge-captura : rotas estaticas + nginx
# ---------------------------------------------------------------------------
# A imagem nginx:alpine traz seu proprio entrypoint (/docker-entrypoint.sh),
# que processa templates e repassa o comando. Em vez de substitui-lo, este
# wrapper instala as rotas das outras zonas e DEPOIS delega para ele, para
# nao perder o comportamento original da imagem.
# ---------------------------------------------------------------------------
set -e

/opt/kovenza/rotas.sh 172.28.20.254

echo "[edge-captura] subindo nginx na porta 8080"
exec /docker-entrypoint.sh "$@"
