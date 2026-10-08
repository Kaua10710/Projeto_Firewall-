# ---------------------------------------------------------------------------
# fw-kovenza - gateway/roteador entre rede_arena, rede_dmz e rede_nuvem
# ---------------------------------------------------------------------------
FROM alpine:3.20

# iptables/ip6tables : motor de filtragem (frontend do Netfilter)
# iproute2           : 'ip route' para inspecionar/ajustar roteamento
# conntrack-tools    : inspecao da tabela de estado (defesa do trabalho)
# tcpdump            : prova opcional de que o pacote chega na interface
RUN apk add --no-cache \
        iptables \
        ip6tables \
        iproute2 \
        conntrack-tools \
        tcpdump

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
