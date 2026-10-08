# ---------------------------------------------------------------------------
# Imagem de ferramentas Alpine
# ---------------------------------------------------------------------------
# Serve a tres conteineres, porque todos sao "um host Linux minimo com
# ferramentas de rede"; o papel de cada um e definido pelo 'command' no
# docker-compose.yml:
#
#   estacao-recepcao -> sleep infinity   (de onde o avaliador roda os testes)
#   camera-rtsp      -> nc -lk -p 554    (simula a camera IP)
#   nuvem-rtmp       -> nc -lk -p 1935   (simula a ingestao do YouTube)
# ---------------------------------------------------------------------------
FROM alpine:3.20

# curl            : testes HTTP/HTTPS positivos
# nmap            : varredura de porta nos testes negativos (-Pn -p N)
# netcat-openbsd  : 'nc -zv' nos testes e 'nc -lk' nos listeners
#                   (o nc do busybox nao tem -k, por isso a versao openbsd)
# bind-tools      : dig/nslookup para demonstrar o limite do DNS do Docker
# iproute2        : 'ip route add' das rotas estaticas
RUN apk add --no-cache \
        curl \
        nmap \
        netcat-openbsd \
        bind-tools \
        iproute2

WORKDIR /opt/kovenza
