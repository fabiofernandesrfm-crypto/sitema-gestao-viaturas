# =============================================================================
# Frontend Flutter Web (PWA) — SGV Sistema de Gestão de Viaturas
# =============================================================================
# Stage 1: Build Flutter Web
# =============================================================================
FROM ghcr.io/cirruslabs/flutter:3.27.0 AS build

WORKDIR /app

# Copia os arquivos de dependências primeiro (cache layer)
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copia o restante do código fonte
COPY . .

# Build otimizado para web com definições de ambiente
# --dart-define=API_BASE_URL pode ser sobrescrito via --build-arg no docker build
ARG API_BASE_URL=/api
RUN flutter build web \
    --release \
    --no-tree-shake-icons \
    --dart-define=API_BASE_URL=${API_BASE_URL}

# =============================================================================
# Stage 2: Servir com nginx (PWA-ready)
# =============================================================================
FROM nginx:1.27-alpine AS serve

# Remove a configuração default do nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia nossa configuração otimizada para PWA
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia os arquivos buildados do Flutter
COPY --from=build /app/build/web /usr/share/nginx/html

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