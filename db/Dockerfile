# ---------------------------------------------------------------------------
# db-local - banco da DMZ (dados de replay e metadados da quadra)
# ---------------------------------------------------------------------------
# Estende a imagem oficial apenas para ter iproute2 disponivel no build.
# Instalar em runtime deixaria a subida do ambiente dependente de rede.
# ---------------------------------------------------------------------------
FROM postgres:16-alpine

RUN apk add --no-cache iproute2

COPY entrypoint.sh /opt/kovenza/entrypoint.sh
RUN chmod +x /opt/kovenza/entrypoint.sh

ENTRYPOINT ["/opt/kovenza/entrypoint.sh"]
CMD ["postgres"]
