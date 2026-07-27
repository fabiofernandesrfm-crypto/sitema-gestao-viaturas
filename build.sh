#!/usr/bin/env bash
# =============================================================================
# SGV — Build Script para Deploy
# =============================================================================
# Uso:
#   chmod +x build.sh
#   ./build.sh                  # Build local com API_BASE_URL=/api
#   ./build.sh prod             # Build produção com domínio da PCPE
#   ./build.sh prod --no-cache  # Rebuild completo sem cache
# =============================================================================
set -euo pipefail

MODE="${1:-local}"
NO_CACHE="${2:-}"

echo "=============================================="
echo " SGV — Build & Deploy"
echo " Modo: ${MODE}"
echo "=============================================="

# Configuração por ambiente
if [ "$MODE" = "prod" ]; then
  export API_BASE_URL="https://analise.policiacivil.pe.gov.br/api"
  export FRONTEND_PORT=80
  echo " 🌐 Ambiente: PRODUÇÃO"
  echo "    API: ${API_BASE_URL}"
else
  export API_BASE_URL="/api"
  export FRONTEND_PORT=8080
  echo " 💻 Ambiente: LOCAL"
  echo "    Frontend: http://localhost:${FRONTEND_PORT}"
  echo "    Backend:  http://localhost:3000/api"
fi

echo ""
echo "📦 Construindo imagens Docker..."
echo ""

if [ "$NO_CACHE" = "--no-cache" ]; then
  docker-compose build --no-cache
else
  docker-compose build
fi

echo ""
echo "✅ Build concluído com sucesso!"
echo ""
echo "📦 Subindo os serviços..."
echo ""

docker-compose up -d

echo ""
echo "🚀 Sistema iniciado!"
echo ""
echo "Para ver os logs:"
echo "  docker-compose logs -f"
echo ""
echo "Para parar:"
echo "  docker-compose down"