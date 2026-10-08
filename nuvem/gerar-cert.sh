#!/bin/sh
# ---------------------------------------------------------------------------
# gerar-cert.sh : certificado autoassinado para o nuvem-supabase
# ---------------------------------------------------------------------------
# Roda no BUILD da imagem, nao no runtime. Assim o material de chave nunca
# e versionado no repositorio (ver .gitignore) e cada build gera o seu.
#
# O certificado nao e assinado por nenhuma autoridade conhecida, portanto os
# testes usam 'curl -k'. Isso e esperado em laboratorio e esta documentado no
# README para o avaliador nao interpretar como falha.
# ---------------------------------------------------------------------------
set -e

DESTINO="/etc/nginx/certs"
mkdir -p "$DESTINO"

openssl req -x509 -nodes \
    -newkey rsa:2048 \
    -days 365 \
    -subj "/C=BR/ST=Goias/L=Ceres/O=Laboratorio Kovenza/CN=nuvem-supabase" \
    -addext "subjectAltName=DNS:nuvem-supabase,IP:172.28.30.10" \
    -keyout "$DESTINO/nuvem-supabase.key" \
    -out "$DESTINO/nuvem-supabase.crt"

chmod 600 "$DESTINO/nuvem-supabase.key"

echo "[gerar-cert] certificado autoassinado criado em $DESTINO"
