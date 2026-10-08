#!/bin/sh
# ---------------------------------------------------------------------------
# db-local : rotas estaticas + entrypoint oficial do Postgres
# ---------------------------------------------------------------------------
# Rodamos como root para poder alterar a tabela de roteamento; o
# docker-entrypoint.sh oficial em seguida rebaixa o processo para o usuario
# 'postgres' por conta propria (gosu), portanto o banco nao fica como root.
# ---------------------------------------------------------------------------
set -e

/opt/kovenza/rotas.sh 172.28.20.254

echo "[db-local] delegando para o entrypoint oficial do Postgres"
exec docker-entrypoint.sh "$@"
