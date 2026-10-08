#!/bin/sh
# ===========================================================================
# testes-negativos.sh - trafego que o firewall precisa barrar
# ===========================================================================
# Um teste negativo pode falhar por DOIS motivos completamente diferentes:
#
#   (a) o firewall recebeu o pacote e descartou   -> segmentacao por desenho
#   (b) nao existia rota e o pacote nunca saiu    -> segmentacao por acidente
#
# No terminal os dois sao identicos: timeout. Para distinguir, cada teste aqui
# zera os contadores do Netfilter antes de rodar e confere depois se a regra
# de DROP correspondente contabilizou pacote. Contador em zero = o bloqueio
# nao aconteceu no firewall, e o ambiente esta certo por sorte.
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

zerar_contadores() {
    $COMPOSE exec -T fw-kovenza iptables -Z FORWARD >/dev/null 2>&1
}

# Le o contador de pacotes da regra cujo comentario contem o rotulo dado.
# Sem --line-numbers, a primeira coluna de 'iptables -L -v -n' e pkts.
contador_da_regra() {
    rotulo="$1"
    $COMPOSE exec -T fw-kovenza iptables -L FORWARD -v -n 2>/dev/null \
        | grep -- "$rotulo" \
        | awk 'NR==1 {print $1}'
}

# $1 = exit status do teste (deve ser DIFERENTE de zero: a conexao deve falhar)
# $2 = rotulo da regra de DROP que deve ter contabilizado
avaliar() {
    status_teste="$1"
    rotulo="$2"
    pacotes=$(contador_da_regra "$rotulo")
    pacotes=${pacotes:-0}

    echo " Contador da regra $rotulo : $pacotes pacote(s)"

    if [ "$status_teste" -eq 0 ]; then
        echo " RESULTADO       : REPROVADO - a conexao foi permitida"
        REPROVADOS=$((REPROVADOS + 1))
        return
    fi

    case "$pacotes" in
        0|"")
            echo " RESULTADO       : REPROVADO - conexao falhou, mas o contador"
            echo "                   ficou em zero: o pacote nao chegou ao"
            echo "                   firewall. Verifique as rotas estaticas."
            REPROVADOS=$((REPROVADOS + 1))
            ;;
        *)
            echo " RESULTADO       : APROVADO - bloqueado PELO FIREWALL"
            APROVADOS=$((APROVADOS + 1))
            ;;
    esac
}

echo "==============================================================="
echo " KOVENZA SPORTS - TESTES NEGATIVOS"
echo " Trafego nao autorizado deve morrer no firewall"
echo "==============================================================="

# ---------------------------------------------------------------------------
# Teste 4 - a recepcao tenta falar direto com o banco da DMZ
# ---------------------------------------------------------------------------
cabecalho "TESTE 4 | recepcao -> banco de dados (TCP 5432)" \
          "R3 DROP" \
          "porta filtrada / timeout"

zerar_contadores
SAIDA=$($COMPOSE exec -T estacao-recepcao \
    nmap -Pn --host-timeout 15s -p 5432 172.28.20.30 2>&1)
echo " Obtido          :"
echo "$SAIDA" | grep -E "^5432|filtered|closed|open" | sed 's/^/                   /'

# Para o nmap, o criterio nao e o exit status (ele sai 0 mesmo filtrando),
# e sim a ausencia da palavra "open" na linha da porta.
echo "$SAIDA" | grep -qE "^5432/tcp\s+open"
if [ $? -eq 0 ]; then avaliar 0 "R3:"; else avaliar 1 "R3:"; fi

# ---------------------------------------------------------------------------
# Teste 5 - a recepcao tenta assistir a camera da quadra
# ---------------------------------------------------------------------------
cabecalho "TESTE 5 | recepcao -> camera IP (TCP 554)" \
          "R2 DROP" \
          "falha de conexao / timeout"

zerar_contadores
SAIDA=$($COMPOSE exec -T estacao-recepcao nc -zv -w 5 172.28.20.20 554 2>&1)
STATUS=$?
echo " Obtido          : ${SAIDA:-timeout sem resposta} (exit $STATUS)"
avaliar $STATUS "R2:"

# ---------------------------------------------------------------------------
# Teste 6 - a camera tenta sair para a internet (phone-home do fabricante)
# ---------------------------------------------------------------------------
# Este e o teste que diferencia o trabalho: defende SAIDA, nao entrada.
# ---------------------------------------------------------------------------
cabecalho "TESTE 6 | camera IP -> nuvem (TCP 443, phone-home)" \
          "R7 DROP" \
          "falha de conexao / timeout"

zerar_contadores
SAIDA=$($COMPOSE exec -T camera-rtsp nc -zv -w 5 172.28.30.10 443 2>&1)
STATUS=$?
echo " Obtido          : ${SAIDA:-timeout sem resposta} (exit $STATUS)"
avaliar $STATUS "R7:"

# ---------------------------------------------------------------------------
# Teste 7 - o mini-PC comprometido tenta pivotar para a rede da arena
# ---------------------------------------------------------------------------
cabecalho "TESTE 7 | mini-PC -> estacao da recepcao (TCP 22)" \
          "R6 DROP" \
          "falha de conexao / timeout"

zerar_contadores
SAIDA=$($COMPOSE exec -T edge-captura nc -zv -w 5 172.28.10.10 22 2>&1)
STATUS=$?
echo " Obtido          : ${SAIDA:-timeout sem resposta} (exit $STATUS)"
avaliar $STATUS "R6:"

# ---------------------------------------------------------------------------
# Evidencia final para o relatorio
# ---------------------------------------------------------------------------
# Cada teste acima zera os contadores para poder atribuir o bloqueio a uma
# regra especifica. O efeito colateral e que, ao final, a chain refletiria
# apenas o ultimo teste. Para a evidencia do relatorio queremos as quatro
# regras de DROP povoadas na mesma listagem, entao zeramos UMA vez e
# repetimos as quatro tentativas em silencio.
# ---------------------------------------------------------------------------
echo ""
echo "==============================================================="
echo " EVIDENCIA | chain FORWARD apos as quatro tentativas"
echo "==============================================================="
echo " Reexecutando os quatro testes negativos sem zerar entre eles,"
echo " para que a listagem mostre todas as regras de DROP povoadas."
echo ""

zerar_contadores
$COMPOSE exec -T estacao-recepcao nmap -Pn --host-timeout 15s -p 5432 172.28.20.30 >/dev/null 2>&1
$COMPOSE exec -T estacao-recepcao nc -zv -w 5 172.28.20.20 554   >/dev/null 2>&1
$COMPOSE exec -T camera-rtsp      nc -zv -w 5 172.28.30.10 443   >/dev/null 2>&1
$COMPOSE exec -T edge-captura     nc -zv -w 5 172.28.10.10 22    >/dev/null 2>&1

$COMPOSE exec -T fw-kovenza iptables -L FORWARD -v -n --line-numbers

echo ""
echo "==============================================================="
echo " RESUMO NEGATIVOS : $APROVADOS aprovado(s), $REPROVADOS reprovado(s)"
echo "==============================================================="
echo " Lembrete: 'aprovado' aqui significa que a conexao falhou E que a"
echo " regra de DROP correspondente contabilizou o pacote."
echo "==============================================================="

[ "$REPROVADOS" -eq 0 ]
