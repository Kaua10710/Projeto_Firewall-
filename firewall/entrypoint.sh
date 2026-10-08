#!/bin/sh
# ===========================================================================
# fw-kovenza - aplicacao automatica das regras de firewall
# Kovenza Sports | Segmentacao da rede de uma arena parceira
# ===========================================================================
# Este script roda como ENTRYPOINT do conteiner, portanto as regras sao
# aplicadas sozinhas em todo "docker compose up" - requisito explicito do
# enunciado. Nao existe passo manual.
#
# A ordem das secoes importa: o Netfilter avalia a chain de cima para baixo e
# o primeiro alvo terminal (ACCEPT/DROP) decide o destino do pacote.
#   conntrack -> ACCEPTs especificos -> DROPs explicitos -> LOG
# ===========================================================================
set -e

ARENA="172.28.10.0/24"
DMZ="172.28.20.0/24"
NUVEM="172.28.30.0/24"

ESTACAO="172.28.10.10"       # computador da recepcao/caixa da arena
EDGE="172.28.20.10"          # mini-PC de captura da Kovenza
CAMERA="172.28.20.20"        # camera IP escolhida pelo cliente
BANCO="172.28.20.30"         # banco local da DMZ
SUPABASE="172.28.30.10"      # API do Supabase (nuvem)
RTMP="172.28.30.20"          # ingestao de video do YouTube (nuvem)

echo "==========================================================="
echo " fw-kovenza : aplicando politica de seguranca"
echo "==========================================================="

# ---------------------------------------------------------------------------
# 1. Encaminhamento de pacotes entre interfaces
# ---------------------------------------------------------------------------
# Sem ip_forward o kernel trata o conteiner como host final e descarta
# qualquer pacote cujo destino nao seja ele mesmo - nenhuma regra de FORWARD
# chegaria a ser avaliada.
#
# O valor e definido em DOIS lugares, de proposito:
#   docker-compose.yml  -> sysctls: net.ipv4.ip_forward=1   (fonte efetiva)
#   este script         -> sysctl -w                        (redundancia)
#
# O 'sysctl -w' aqui normalmente FALHA, e isso e esperado: quando o Compose
# declara um sysctl, o Docker monta /proc/sys como somente-leitura dentro do
# conteiner. Por isso a tentativa e tolerada. O que nao e tolerado e o valor
# final estar errado - a verificacao abaixo aborta a subida nesse caso, em vez
# de deixar um firewall que nao encaminha nada parecendo saudavel.
# ---------------------------------------------------------------------------
if sysctl -w net.ipv4.ip_forward=1 2>/dev/null; then
    echo "[1/6] ip_forward definido por este script"
else
    echo "[1/6] /proc/sys e somente-leitura; valor vem do sysctls do compose"
fi

IP_FORWARD="$(cat /proc/sys/net/ipv4/ip_forward)"
if [ "$IP_FORWARD" != "1" ]; then
    echo "[1/6] ERRO: ip_forward = $IP_FORWARD (esperado 1)." >&2
    echo "       Sem encaminhamento o firewall nao roteia entre as zonas." >&2
    echo "       Confira 'sysctls' do servico fw-kovenza no docker-compose.yml." >&2
    exit 1
fi
echo "[1/6] ip_forward = $IP_FORWARD (confirmado)"

# ---------------------------------------------------------------------------
# 2. Limpar estado anterior
# ---------------------------------------------------------------------------
# Garante que o conteiner reiniciado nao acumule regras duplicadas.
# ---------------------------------------------------------------------------
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X
echo "[2/6] chains limpas (filter, nat, mangle)"

# ---------------------------------------------------------------------------
# 3. Politica padrao: negar tudo
# ---------------------------------------------------------------------------
# REGRA 9 da matriz. A politica e o ultimo recurso da chain: o que nao foi
# explicitamente liberado acima morre aqui. OUTPUT fica ACCEPT porque o
# proprio firewall nao e um host de usuario e precisa poder responder.
# ---------------------------------------------------------------------------
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT
echo "[3/6] politica padrao: INPUT=DROP FORWARD=DROP OUTPUT=ACCEPT"

# ---------------------------------------------------------------------------
# 4. Trafego de retorno de conexoes ja estabelecidas
# ---------------------------------------------------------------------------
# Obrigatorio. Uma conexao TCP tem dois sentidos; se so o SYN de ida for
# liberado, o SYN/ACK de volta bate na politica DROP e tudo parece quebrado.
# O conntrack reconhece o pacote como pertencente a um fluxo ja autorizado.
# ---------------------------------------------------------------------------
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED \
    -m comment --comment "CONNTRACK: retorno de conexoes autorizadas" -j ACCEPT
echo "[4/6] conntrack ESTABLISHED,RELATED liberado"

# ---------------------------------------------------------------------------
# 5. Regras explicitas da matriz de seguranca
# ---------------------------------------------------------------------------
echo "[5/6] aplicando a matriz de regras..."

# --- ACCEPTs especificos ---------------------------------------------------

# R1 | Rede Arena -> edge-captura TCP 8080 | ACCEPT
# Negocio: o dono da arena precisa conferir se a quadra esta transmitindo.
iptables -A FORWARD -s "$ARENA" -d "$EDGE" -p tcp --dport 8080 \
    -m comment --comment "R1: arena -> painel da quadra 8080" -j ACCEPT

# R4 | edge-captura -> nuvem-supabase TCP 443 | ACCEPT
# Negocio: publicar o replay e informar o estado da quadra.
iptables -A FORWARD -s "$EDGE" -d "$SUPABASE" -p tcp --dport 443 \
    -m comment --comment "R4: edge -> supabase 443" -j ACCEPT

# R5 | edge-captura -> nuvem-rtmp TCP 1935 | ACCEPT
# Negocio: transmissao ao vivo da partida.
iptables -A FORWARD -s "$EDGE" -d "$RTMP" -p tcp --dport 1935 \
    -m comment --comment "R5: edge -> ingest rtmp 1935" -j ACCEPT

# R8 | camera-rtsp -> edge-captura TCP 554 | ACCEPT
# Negocio: apenas o mini-PC consome o video da camera.
# ATENCAO (ver RELATORIO, secao 4.4): camera e edge estao na MESMA bridge
# (rede_dmz), portanto esse trafego NAO atravessa o firewall e a regra nunca
# contabiliza pacote. Ela fica declarada para registrar a intencao de projeto;
# em producao a camera moraria numa quarta zona para a regra ser aplicavel.
iptables -A FORWARD -s "$CAMERA" -d "$EDGE" -p tcp --dport 554 \
    -m comment --comment "R8: camera -> edge 554 (intra-DMZ)" -j ACCEPT

# --- DROPs explicitos ------------------------------------------------------
# Redundantes com a politica padrao, mas essenciais como prova: aparecem em
# "iptables -L FORWARD -v -n" com contador de pacotes, demonstrando que a
# tentativa chegou ao firewall e foi barrada - e nao que ninguem tentou.

# R2 | Rede Arena -> camera-rtsp TCP 554 | DROP
# Negocio: a imagem ao vivo da quadra nao tem autenticacao; exibi-la na rede
# da arena exporia os jogadores.
iptables -A FORWARD -s "$ARENA" -d "$CAMERA" -p tcp --dport 554 \
    -m comment --comment "R2: arena -X camera 554" -j DROP

# R3 | Rede Arena -> db-local TCP 5432 | DROP
# Negocio: o banco guarda dados pessoais e nunca e acessado diretamente por
# estacao de trabalho.
iptables -A FORWARD -s "$ARENA" -d "$BANCO" -p tcp --dport 5432 \
    -m comment --comment "R3: arena -X banco 5432" -j DROP

# R6 | edge-captura -> Rede Arena (qualquer) | DROP
# Negocio: se o mini-PC for comprometido, ele nao alcanca a rede
# administrativa da arena.
iptables -A FORWARD -s "$EDGE" -d "$ARENA" \
    -m comment --comment "R6: edge -X arena (anti-pivot)" -j DROP

# R7 | camera-rtsp -> Nuvem (qualquer) | DROP
# Negocio: impede o phone-home do fabricante da camera, que enviaria imagem
# para fora sem consentimento. Defesa de SAIDA, nao de entrada.
iptables -A FORWARD -s "$CAMERA" -d "$NUVEM" \
    -m comment --comment "R7: camera -X nuvem (anti phone-home)" -j DROP

# Fechamento da DMZ para a arena: qualquer host da DMZ, nao apenas o edge.
iptables -A FORWARD -s "$DMZ" -d "$ARENA" \
    -m comment --comment "R6b: DMZ -X arena (generalizacao de R6)" -j DROP

# ---------------------------------------------------------------------------
# 6. Registro do que foi bloqueado
# ---------------------------------------------------------------------------
# Ultima regra antes da politica: tudo que sobreviveu as regras acima e, por
# definicao, trafego nao autorizado. O LOG nao decide destino do pacote (nao
# e alvo terminal), entao o pacote segue e morre no DROP explicito seguinte.
#
# No Docker Desktop/Windows o kernel log nao chega ao dmesg do conteiner, logo
# as linhas podem nao ser visiveis. O contador de pacotes da regra, sim.
# ---------------------------------------------------------------------------
iptables -A FORWARD -m limit --limit 10/min \
    -m comment --comment "R9: log do descarte padrao" \
    -j LOG --log-prefix "KOVENZA-FW-DROP: " --log-level 4
iptables -A FORWARD \
    -m comment --comment "R9: politica padrao, descarte explicito" -j DROP
echo "[6/6] LOG + DROP final instalados"

echo ""
echo "==========================================================="
echo " Chain FORWARD ativa"
echo "==========================================================="
iptables -L FORWARD -v -n --line-numbers
echo ""
echo "fw-kovenza pronto. Politica em vigor."

exec sleep infinity
