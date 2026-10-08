# ---------------------------------------------------------------------------
# edge-captura - simula o mini-PC de captura instalado na quadra
# ---------------------------------------------------------------------------
FROM nginx:alpine

# iproute2        : 'ip route add' das rotas estaticas (exige NET_ADMIN)
# curl            : testes positivos partindo da DMZ para a nuvem
# netcat-openbsd  : 'nc -zv' nos testes de porta
RUN apk add --no-cache iproute2 curl netcat-openbsd

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html/health.json /usr/share/nginx/html/health.json
COPY entrypoint.sh /opt/kovenza/entrypoint.sh
RUN chmod +x /opt/kovenza/entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/opt/kovenza/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
