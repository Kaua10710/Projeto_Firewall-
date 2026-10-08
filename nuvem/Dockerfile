# ---------------------------------------------------------------------------
# nuvem-supabase - simula a API do Supabase (HTTPS)
# ---------------------------------------------------------------------------
FROM nginx:alpine

RUN apk add --no-cache iproute2 openssl curl

COPY gerar-cert.sh /opt/kovenza/gerar-cert.sh
RUN chmod +x /opt/kovenza/gerar-cert.sh && /opt/kovenza/gerar-cert.sh

COPY nginx-tls.conf /etc/nginx/conf.d/default.conf
COPY entrypoint.sh /opt/kovenza/entrypoint.sh
RUN chmod +x /opt/kovenza/entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/opt/kovenza/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
