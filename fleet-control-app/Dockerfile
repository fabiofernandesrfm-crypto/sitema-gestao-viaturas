# =============================================================================
# Frontend Flutter Web (PWA) — SGV Sistema de Gestão de Viaturas
# =============================================================================
# Multi-stage build:
#   Stage 1: Compila o projeto Flutter Web (Flutter SDK via Git oficial)
#   Stage 2: Serve os arquivos estáticos via Nginx
# =============================================================================

# ---- Stage 1: Build Flutter Web ----
FROM debian:bookworm-slim AS build

# Versão do Flutter a ser instalada
ARG FLUTTER_VERSION=3.22.3

# Argumento de build para definir a URL base da API
ARG API_BASE_URL=/api
ENV API_BASE_URL=${API_BASE_URL}

# Instala dependências essenciais do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    ca-certificates \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Clona o SDK oficial do Flutter diretamente do repositório Git oficial
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git /opt/flutter

# Adiciona o Flutter ao PATH
ENV PATH="/opt/flutter/bin:${PATH}"

# Pre-cache dos artefatos do Flutter Web (evita downloads repetidos)
RUN flutter config --no-analytics && \
    flutter precache --web

WORKDIR /app

# Copia os arquivos de dependências primeiro (para cache de camadas Docker)
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copia o restante do código fonte do projeto Flutter
COPY . .

# Build do Flutter Web em modo release
# --no-tree-shake-icons: mantém todos os ícones Material Icons
# --dart-define: define a variável de compilação API_BASE_URL usada pelo ApiConfig
RUN flutter build web --release \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --no-tree-shake-icons

# ---- Stage 2: Serve com Nginx ----
FROM nginx:1.27-alpine

# Remove a configuração default do nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia nossa configuração otimizada para PWA
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia os arquivos já buildados do Stage 1
COPY --from=build /app/build/web /usr/share/nginx/html

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