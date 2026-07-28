FROM nginx:1.27-alpine

# Remove configuração padrão do Nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia configuração personalizada do Nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Define diretório de trabalho
WORKDIR /usr/share/nginx/html

# Copia arquivos gerados pelo Flutter Web para o diretório raiz do Nginx.
# O trailing slash em build/web/ garante que o CONTEÚDO da pasta seja copiado
# diretamente para /usr/share/nginx/html, e não que a pasta em si seja copiada.
COPY build/web/ ./

# Ajusta permissões para o usuário nginx (non-root)
RUN chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /var/log/nginx && \
    chmod -R 755 /usr/share/nginx/html

# Healthcheck básico para o Nginx
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || exit 1

EXPOSE 80

# Executa como usuário não-root por segurança
USER nginx

CMD ["nginx", "-g", "daemon off;"]
