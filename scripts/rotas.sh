#!/bin/sh
# ---------------------------------------------------------------------------
# rotas.sh - rotas estaticas das zonas para o firewall
# ---------------------------------------------------------------------------
# POR QUE ISSO EXISTE
#
# No Docker, conteineres da MESMA rede bridge conversam direto, sem gateway.
# Para que o firewall realmente filtre, cada zona esta numa bridge separada e
# so o fw-kovenza participa das tres. O efeito colateral e que, por padrao,
# as zonas nao se enxergam: a unica rota que o Docker instala para fora da
# propria sub-rede e a default, que aponta para o gateway da bridge no host.
#
# Este script instala rotas /24 explicitas apontando as outras duas zonas para
# o IP do firewall. Uma rota /24 e mais especifica que a default (0.0.0.0/0),
# portanto vence na tabela de roteamento e o pacote sobe para o fw-kovenza.
#
# Exige cap_add: [NET_ADMIN] no conteiner - nao basta no firewall.
#
# Uso: rotas.sh <IP-do-firewall-nesta-rede>
# ---------------------------------------------------------------------------
set -e

GW="$1"

if [ -z "$GW" ]; then
    echo "[rotas] ERRO: informe o IP do firewall nesta rede. Ex: rotas.sh 172.28.10.254" >&2
    exit 1
fi

ARENA="172.28.10.0/24"
DMZ="172.28.20.0/24"
NUVEM="172.28.30.0/24"

case "$GW" in
    172.28.10.254) DESTINOS="$DMZ $NUVEM"   ; ZONA="rede_arena" ;;
    172.28.20.254) DESTINOS="$ARENA $NUVEM" ; ZONA="rede_dmz"   ;;
    172.28.30.254) DESTINOS="$ARENA $DMZ"   ; ZONA="rede_nuvem" ;;
    *)
        echo "[rotas] ERRO: gateway '$GW' nao corresponde a nenhuma zona conhecida." >&2
        exit 1
        ;;
esac

echo "[rotas] zona=$ZONA gateway=$GW"

for destino in $DESTINOS; do
    # Remove eventual rota anterior para deixar o script idempotente.
    ip route del "$destino" 2>/dev/null || true

    if ip route add "$destino" via "$GW" 2>/dev/null; then
        echo "[rotas]   + $destino via $GW"
    else
        # Fallback para imagens que trazem apenas o 'route' do busybox.
        rede="${destino%/*}"
        if route add -net "$rede" netmask 255.255.255.0 gw "$GW" 2>/dev/null; then
            echo "[rotas]   + $destino via $GW (via busybox route)"
        else
            echo "[rotas]   ! falhou ao adicionar $destino via $GW" >&2
            exit 1
        fi
    fi
done

echo "[rotas] tabela final:"
ip route 2>/dev/null || route -n
