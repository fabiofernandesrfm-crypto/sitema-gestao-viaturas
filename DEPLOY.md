# 🚀 Deploy no Easypanel — SGV Sistema de Gestão de Viaturas

Este guia descreve o passo a passo para publicar o sistema completo no Easypanel usando Docker Compose.

---

## 📋 Pré-requisitos

- Conta no Easypanel com acesso a um servidor Linux (Ubuntu 22.04+)
- Repositório Git com o código fonte (GitHub, GitLab, etc.)
- Docker instalado no servidor (gerenciado pelo Easypanel)

---

## 🏗️ Arquitetura do Deploy

```
┌─────────────────────────────────────────────┐
│                  Easypanel                   │
│                                             │
│  ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │ Frontend │   │ Backend  │   │   DB    │ │
│  │ (nginx)  │──▶│ (Node.js)│──▶│(Postgre)│ │
│  │  :80     │   │  :3000   │   │  :5432  │ │
│  └──────────┘   └──────────┘   └─────────┘ │
│       │                                    │
│       ▼                                    │
│  Usuário acessa apenas a porta 80          │
│  O nginx faz proxy reverso para o backend  │
│  na rota /api/*                            │
└─────────────────────────────────────────────┘
```

---

## 📦 Passo 1 — Preparar o repositório

Certifique-se de que o repositório contém todos os arquivos de deploy:

```
├── docker-compose.yml          # Orquestração principal (usado pelo Easypanel)
├── .env.example               # Template de variáveis de ambiente
├── DEPLOY.md                   # Este guia
├── fleet-control-backend/
│   ├── Dockerfile              # Build da API Node.js
│   ├── server.js               # Código fonte do backend
│   ├── db.js                   # Conexão PostgreSQL
│   ├── package.json
│   └── .dockerignore
└── fleet-control-app/
    ├── Dockerfile              # Build multi-stage Flutter Web + nginx
    ├── nginx.conf              # Configuração nginx (SPA + proxy reverso)
    ├── pubspec.yaml
    └── .dockerignore
```

---

## 🔧 Passo 2 — Configurar variáveis de ambiente no Easypanel

No Easypanel, ao criar o serviço "Compose App", defina as seguintes variáveis:

| Variável | Valor | Descrição |
|---|---|---|
| `DB_PASSWORD` | `senha_segura_aqui` | Senha do banco PostgreSQL |
| `API_BASE_URL` | `/api` | URL da API (use `/api` para proxy reverso) |
| `FRONTEND_PORT` | `80` | Porta pública do frontend |

**Exemplo de configuração no Easypanel:**
```
DB_PASSWORD=MinhaSenhaSegura2026!
API_BASE_URL=/api
FRONTEND_PORT=80
```

> ⚠️ **Importante:** Altere a senha padrão do banco! A senha padrão `sgv_password_2024` é apenas para desenvolvimento.

---

## 🚢 Passo 3 — Criar o App no Easypanel

1. Acesse o painel do Easypanel
2. Clique em **"Create"** → **"App"**
3. Selecione **"Docker Compose"**
4. Escolha a fonte:
   - **Git Repository**: aponte para o repositório
   - **Raw Compose**: cole o conteúdo do `docker-compose.yml` diretamente
5. Configure as variáveis de ambiente conforme a tabela acima
6. Defina o domínio (ex: `sgv.policiacivil.pe.gov.br`)
7. Habilite **HTTPS** (Let's Encrypt) — o Easypanel gerencia automaticamente

---

## 🌐 Passo 4 — Configurar Domínio e SSL

1. No Easypanel, vá até as configurações do serviço **frontend**
2. Em **"Domains"**, adicione o domínio desejado
3. Marque **"Enable SSL"** para gerar certificado Let's Encrypt automaticamente
4. O Easypanel adiciona o proxy reverso com HTTPS automaticamente

**Fluxo HTTPS:**
```
Usuário → https://sgv.policiacivil.pe.gov.br → Easypanel (SSL) → nginx:80 → /api → backend:3000
```

---

## 🗄️ Passo 5 — Banco de Dados (Opcional — DB Externo)

Se preferir usar um banco de dados externo (ex: serviço gerenciado da DigitalOcean, AWS RDS, etc.):

1. Remova o serviço `db` do `docker-compose.yml`
2. Atualize `DATABASE_URL` no serviço `backend`:
   ```
   DATABASE_URL=postgresql://usuario:senha@host-externo:5432/sgv_viaturas
   ```

Para usar o banco incluso no compose (recomendado para simplicidade), mantenha a configuração padrão.

---

## 📝 Passo 6 — Verificar o Deploy

Após o deploy, verifique:

```bash
# 1. Status dos containers
docker compose ps

# 2. Logs do backend
docker compose logs -f backend

# 3. Logs do frontend
docker compose logs -f frontend

# 4. Testar a API diretamente
curl http://localhost:3000/
# Deve retornar: {"status":"API do SGV-Viaturas online!"}

# 5. Testar via proxy reverso
curl http://localhost/api/
# Deve retornar o mesmo que acima
```

---

## 🔄 Atualizações e Redeploy

Para atualizar o sistema após mudanças no código:

```bash
# 1. Pull das alterações
git pull origin main

# 2. Rebuild e restart
docker compose down
docker compose build --no-cache
docker compose up -d

# 3. Verificar logs
docker compose logs -f
```

---

## ⚙️ Configurações Específicas do Easypanel

### Resource Limits (recomendado)
| Serviço | CPU | RAM |
|---|---|---|
| frontend | 0.5 vCPU | 256 MB |
| backend | 1 vCPU | 512 MB |
| db | 1 vCPU | 1 GB |

### Health Checks
Os containers já incluem healthchecks configurados:
- **backend**: `GET /` retorna 200 → serviço saudável
- **frontend**: nginx responde na porta 80 → serviço saudável
- **db**: `pg_isready` → banco pronto para conexões

### Persistência de Dados
- Volume `sgv_pgdata`: dados do PostgreSQL
- Volume `sgv_pgadmin_data`: configurações do PgAdmin (opcional)

---

## 🛠️ Troubleshooting

### Erro: "Connection refused" ao acessar a API
- Verifique se o serviço `backend` está rodando: `docker compose ps backend`
- Verifique se a rede `sgv-network` está criada: `docker network ls`
- Teste a conexão interna: `docker compose exec frontend wget -qO- http://backend:3000/`

### Erro: Flutter build falha
- Verifique a versão do Flutter no Dockerfile (use uma versão estável)
- O build do Flutter Web requer no mínimo 2 GB de RAM disponível
- Para builds mais rápidos, use `--no-tree-shake-icons`

### Erro: Tabelas não criadas
O backend cria automaticamente as tabelas na inicialização via `CREATE TABLE IF NOT EXISTS`. Se houver erro, verifique:
- A conexão com o banco: `docker compose logs backend | grep -i "erro"`
- As migrations são executadas em sequência no startup do `server.js`

---

## 📁 Estrutura Final de Arquivos para Deploy

```
.
├── docker-compose.yml          # ← Easypanel importa este arquivo
├── .env.example               # ← Template (crie .env com valores reais)
├── build.sh                   # ← Script auxiliar de build local
├── DEPLOY.md                   # ← Este guia
├── fleet-control-backend/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── server.js
│   ├── db.js
│   └── package.json
└── fleet-control-app/
    ├── Dockerfile
    ├── .dockerignore
    ├── nginx.conf
    └── pubspec.yaml