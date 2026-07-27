# =============================================================================
# Frontend Flutter Web (PWA) — SGV Sistema de Gestão de Viaturas
# =============================================================================
# Este Dockerfile NÃO faz o build do Flutter.
# O build web deve ser executado localmente antes com:
#   cd fleet-control-app && flutter build web --release --no-tree-shake-icons
# O Easypanel apenas servirá os arquivos estáticos prontos via Nginx.
# =============================================================================
FROM nginx:1.27-alpine

# Remove a configuração default do nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia nossa configuração otimizada para PWA
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia os arquivos já buildados do Flutter Web
COPY build/web /usr/share/nginx/html

# Adiciona headers específicos para PWA
RUN echo '{\
  "name": "SGV - Polícia Civil de Pernambuco",\
  "short_name": "SGV-PCPE",\
  "description": "Sistema de Gestão de Viaturas - PCPE",\
  "start_url": "/",\
  "display": "standalone",\
  "background_color": "#0F172A",\
  "theme_color": "#0F172A",\
  "icons": [\
    {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},\
    {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"}\
  ]\
}' > /usr/share/nginx/html/manifest.json

# Cria ícones PWA placeholder se não existirem
RUN mkdir -p /usr/share/nginx/html/icons && \
    (test -f /usr/share/nginx/html/icons/Icon-192.png || \
     echo "placeholder" > /usr/share/nginx/html/icons/Icon-192.png) && \
    (test -f /usr/share/nginx/html/icons/Icon-512.png || \
     echo "placeholder" > /usr/share/nginx/html/icons/Icon-512.png)

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]