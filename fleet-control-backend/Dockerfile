FROM node:18-alpine

WORKDIR /app

# Copia os arquivos de dependências
COPY package*.json ./

# Instala as dependências
RUN npm ci --only=production

# Copia o código da aplicação
COPY . .

# Expõe a porta da API
EXPOSE 3000

# Comando para iniciar a aplicação
CMD ["node", "server.js"]