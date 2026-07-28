# =============================================================================
# SGV Frontend — Multi-stage Docker Build
# Stage 1: Compila o Flutter Web
# Stage 2: Serve via Nginx
# =============================================================================

# ========================================
# Stage 1 — Build Flutter Web
# ========================================
FROM dart:3.7-stable AS build

# Instala dependências para build Flutter Web
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    unzip \
    xz-utils \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Instala Flutter SDK
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
RUN git clone --depth 1 --branch stable https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && flutter config --no-analytics \
    && flutter precache --web

# Define diretório de trabalho
WORKDIR /app

# Copia arquivos de dependências primeiro (para cache de camadas)
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copia o restante do código fonte
COPY lib/ ./lib/
COPY web/ ./web/
COPY assets/ ./assets/

# Build Flutter Web
RUN flutter build web --release --no-tree-shake-icons

# ========================================
# Stage 2 — Serve com Nginx
# ========================================
FROM nginx:1.27-alpine

# Remove configuração padrão do Nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia configuração personalizada do Nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia os arquivos compilados do Flutter Web do estágio de build
# O trailing slash em build/web/ garante que o CONTEÚDO da pasta seja copiado
# diretamente para /usr/share/nginx/html, e não a pasta em si.
COPY --from=build /app/build/web/ /usr/share/nginx/html/

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