# Plano: Setup docker-framework para VoiceTranscription (squad `av`)

## Context

O projeto `VoiceTranscription` está registrado em `config/squads.yml` (squad `av`, index 3, projeto `hv_stt`, index 1 → prefixo de porta **31**), mas a pasta `project-hv/VoiceTranscription/` está vazia. Nenhum `df.yml`, nenhum `docker-compose.yml` de serviço foi criado ainda.

O objetivo é integrar os três repositórios existentes ao docker-framework para que `df start` suba toda a stack local:

- **API** — `/repos/_hv/STT/VoiceTranscription.AI.Api` (.NET 8, já tem Dockerfile)
- **Web** — `/repos/_hv/STT/VoiceTranscription.AI.Web` (React/Vite, **sem** Dockerfile)
- **Consumer** — `/repos/_hv/STT/VoiceTranscription.AI.Consumer` (.NET 8, já tem Dockerfile)

Infra necessária: **Redis** (via template do framework → porta **31379**).

---

## Decisões tomadas

| Decisão | Escolha |
|---------|---------|
| Web container | Dev server Vite com HMR (volume mount do código-fonte) |
| Redis | Infra via framework (`templates/redis`) |
| API / Consumer | Build local (`build: context:` no docker-compose) |

---

## Arquivos a criar

### 1. `project-hv/VoiceTranscription/df.yml`

Manifesto do projeto. Declara dependências de infra e serviços:

```yaml
project:
  name: hv_stt
  squad: av

dependencies:
  infra:
    - redis
  services:
    - api
    - web
    - consumer
```

---

### 2. `project-hv/VoiceTranscription/docker-compose.yml`

Arquivo único com os três serviços (o framework injeta as env vars via `.env` temporário gerado por `config.sh`):

```yaml
services:

  api:
    build:
      context: /repos/_hv/STT/VoiceTranscription.AI.Api/src
      dockerfile: Dockerfile
    container_name: hv_stt-api
    ports:
      - "${HOST_PORT_API:-8080}:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__Redis: "infra-hv_stt-redis:6379"
    networks:
      - df-network
    labels:
      managed-by: docker-framework
      df.type: project
      df.project: hv_stt
    restart: unless-stopped

  consumer:
    build:
      context: /repos/_hv/STT/VoiceTranscription.AI.Consumer/src
      dockerfile: Dockerfile
    container_name: hv_stt-consumer
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__Redis: "infra-hv_stt-redis:6379"
    networks:
      - df-network
    labels:
      managed-by: docker-framework
      df.type: project
      df.project: hv_stt
    restart: unless-stopped

  web:
    build:
      context: /repos/_hv/STT/VoiceTranscription.AI.Web
      dockerfile: Dockerfile
    container_name: hv_stt-web
    ports:
      - "${HOST_PORT_WEB:-5173}:5173"
    volumes:
      - /repos/_hv/STT/VoiceTranscription.AI.Web/src:/app/src
      - /repos/_hv/STT/VoiceTranscription.AI.Web/index.html:/app/index.html
    networks:
      - df-network
    labels:
      managed-by: docker-framework
      df.type: project
      df.project: hv_stt
    restart: unless-stopped

networks:
  df-network:
    name: df-network
    external: true
```

> Portas `HOST_PORT_API` e `HOST_PORT_WEB` podem ser fixas ou controladas pelo `.env.example`.

---

### 3. `VoiceTranscription.AI.Web/Dockerfile` *(novo)*

Dev server Vite com HMR:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
```

O código-fonte (`src/`, `index.html`) é montado via volume no `docker-compose.yml` acima para que o HMR funcione sem rebuild.

---

### 4. `project-hv/VoiceTranscription/.env.example`

Documenta variáveis de ambiente opcionais/secretas que o desenvolvedor deve copiar para `.env`:

```env
# Portas expostas dos serviços (opcional — geradas automaticamente pelo framework)
HOST_PORT_API=8080
HOST_PORT_WEB=5173

# GCP (obrigatório)
GOOGLE_APPLICATION_CREDENTIALS=/path/to/gcp-key.json
GCP_PROJECT_ID=prj-hap-ti-vtx-voice-trsc-dev

# Vertex AI / GCS (já definido em appsettings.json, sobrescrever aqui se necessário)
# VERTEX_AI_MODEL=gemini-2.5-flash
# GCS_BUCKET=prj-hap-ti-vic-tsc-dev
```

---

## Ordem de execução

1. Criar `VoiceTranscription.AI.Web/Dockerfile`
2. Criar `project-hv/VoiceTranscription/df.yml`
3. Criar `project-hv/VoiceTranscription/docker-compose.yml`
4. Criar `project-hv/VoiceTranscription/.env.example`
5. Verificar `config/squads.yml` — confirmar que `av → hv_stt` já está registrado (✅ confirmado na exploração)

---

## Verificação

```bash
# A partir de project-hv/VoiceTranscription/
df start

# Deve:
# 1. Subir infra-hv_stt-redis na porta 31379
# 2. Buildar e subir hv_stt-api, hv_stt-web, hv_stt-consumer na df-network
# 3. df status → mostrar todos os containers como Running

df log api -f        # logs da API
df log web -f        # logs do Vite dev server
df log consumer -f   # logs do Consumer
```
