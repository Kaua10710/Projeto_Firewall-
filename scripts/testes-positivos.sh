#!/bin/sh
# ===========================================================================
# testes-positivos.sh - trafego que o negocio precisa que funcione
# ===========================================================================
# Roda no HOST (precisa do docker na linha de comando), nao dentro de um
# conteiner. No Windows, use Git Bash, WSL ou PowerShell com "sh".
#
# Cada teste imprime O QUE SE ESPERA antes de executar, para que o resultado
# possa ser conferido sem conhecer a matriz de cor.
# ===========================================================================

COMPOSE="docker compose"
APROVADOS=0
REPROVADOS=0

cabecalho() {
    echo ""
    echo "---------------------------------------------------------------"
    echo " $1"
    echo "---------------------------------------------------------------"
    echo " Regra da matriz : $2"
    echo " Esperado        : $3"
}

resultado() {
    # $1 = 0 se o teste passou
    if [ "$1" -eq 0 ]; then
        echo " RESULTADO       : APROVADO"
        APROVADOS=$((APROVADOS + 1))
    else
        echo " RESULTADO       : REPROVADO"
        REPROVADOS=$((REPROVADOS + 1))
    fi
}

echo "==============================================================="
echo " KOVENZA SPORTS - TESTES POSITIVOS"
echo " Trafego legitimo deve atravessar o firewall"
echo "==============================================================="

# ---------------------------------------------------------------------------
# Teste 1 - a recepcao da arena consulta o painel de estado da quadra
# ---------------------------------------------------------------------------
cabecalho "TESTE 1 | recepcao -> painel da quadra (TCP 8080)" \
          "R1 ACCEPT" \
          "HTTP 200"

CODIGO=$($COMPOSE exec -T estacao-recepcao \
    curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
    http://172.28.20.10:8080/health 2>/dev/null)

echo " Obtido          : HTTP ${CODIGO:-sem resposta}"
[ "$CODIGO" = "200" ]
resultado $?

# ---------------------------------------------------------------------------
# Teste 2 - o mini-PC publica o replay no Supabase
# ---------------------------------------------------------------------------
# O -k e obrigatorio: o nuvem-supabase usa certificado autoassinado gerado no
# build. Nao e falha de configuracao, e o esperado em laboratorio.
# ---------------------------------------------------------------------------
cabecalho "TESTE 2 | mini-PC -> Supabase (TCP 443, TLS)" \
          "R4 ACCEPT" \
          "HTTP 200"

CODIGO=$($COMPOSE exec -T edge-captura \
    curl -k -s -o /dev/null -w "%{http_code}" --max-time 8 \
    https://172.28.30.10 2>/dev/null)

echo " Obtido          : HTTP ${CODIGO:-sem resposta}"
[ "$CODIGO" = "200" ]
resultado $?

# ---------------------------------------------------------------------------
# Teste 3 - o mini-PC alcanca a ingestao de video ao vivo
# ---------------------------------------------------------------------------
cabecalho "TESTE 3 | mini-PC -> ingestao RTMP (TCP 1935)" \
          "R5 ACCEPT" \
          "porta aberta (conexao estabelecida)"

SAIDA=$($COMPOSE exec -T edge-captura nc -zv -w 5 172.28.30.20 1935 2>&1)
STATUS=$?

echo " Obtido          : ${SAIDA:-sem saida} (exit $STATUS)"
[ "$STATUS" -eq 0 ]
resultado $?

# ---------------------------------------------------------------------------
# Evidencia: contadores das regras de ACCEPT devem ter subido
# ---------------------------------------------------------------------------
echo ""
echo "==============================================================="
echo " EVIDENCIA | contadores das regras de ACCEPT"
echo "==============================================================="
echo " Se os contadores abaixo estao acima de zero, o pacote realmente"
echo " passou pelo firewall e foi autorizado por regra - nao por acaso."
echo ""
$COMPOSE exec -T fw-kovenza iptables -L FORWARD -v -n --line-numbers \
    | grep -E "num|R1:|R4:|R5:"

echo ""
echo "==============================================================="
echo " RESUMO POSITIVOS : $APROVADOS aprovado(s), $REPROVADOS reprovado(s)"
echo "==============================================================="

[ "$REPROVADOS" -eq 0 ]
