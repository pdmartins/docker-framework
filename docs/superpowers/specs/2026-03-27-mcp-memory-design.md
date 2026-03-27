# Design: projeto mcp-memory no docker-framework

**Data:** 2026-03-27
**Squad:** pm
**Projeto:** mcp-memory

---

## Contexto

O [MCP Memory Server](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) é uma implementação de memória persistente usando um grafo de conhecimento local (arquivo JSONL). Ele permite que agentes Claude Code lembrem informações entre sessões e projetos.

Este documento descreve como integrar esse servidor ao docker-framework como um projeto sempre disponível na squad `pm`.

---

## Objetivo

Disponibilizar o MCP Memory Server como um container Docker sempre ativo, acessível via SSE por todos os projetos do docker-framework, com memórias organizadas por entidade-projeto dentro de um único grafo de conhecimento global.

---

## Decisões de design

### Transporte
O MCP Memory Server suporta stdio (padrão) e SSE. Para uso como daemon em rede, utilizamos **SSE** (`--transport sse`), que expõe o servidor via HTTP.

### Storage
Um único arquivo `global.jsonl` com bind mount em `./data/` no host (`/repos/_pm/docker-framework/project-pm/mcp-memory/data/global.jsonl`). Sem banco de dados externo.

### Isolamento entre projetos
Como o `MEMORY_FILE_PATH` é lido na inicialização do processo (não por requisição), um único container serve um único arquivo JSONL. O isolamento é feito **por convenção no grafo**:

- Cada projeto cria uma entidade do tipo `project-context` com seu slug (ex: `obsidian`, `mcp-memory`)
- Todas as memórias relacionadas a um projeto são associadas à entidade correspondente
- Agentes são instruídos via system prompt a seguir essa convenção

### Porta
Calculada pelo docker-framework: squad `pm` (index 2), projeto `mcp-memory` (index 2):
```
(2 * 10 + 2) * 1000 + 001 = 22001
```
Porta base de referência: `3001` → últimos 3 dígitos: `001`.

---

## Estrutura de arquivos

```
project-pm/
└── mcp-memory/
    ├── df.yml                        ← manifesto do projeto
    ├── mcp-memory/                   ← subdiretório do serviço (convenção do framework)
    │   └── docker-compose.yml        ← definição do container
    └── data/
        └── global.jsonl              ← storage do grafo (criado automaticamente)
```

> **Convenção do framework:** o campo `dependencies.services` resolve o `docker-compose.yml` em `{app_dir}/{service_name}/docker-compose.yml`. Por isso o compose fica em `mcp-memory/mcp-memory/docker-compose.yml`.

---

## Arquivos do projeto

### `df.yml`
```yaml
project:
  name: mcp-memory
  squad: pm

dependencies:
  services:
    - mcp-memory
```

### `mcp-memory/docker-compose.yml`
```yaml
services:
  mcp-memory:
    image: node:lts-alpine
    container_name: ${PROJECT_SLUG}
    restart: unless-stopped
    command: npx -y @modelcontextprotocol/server-memory --transport sse
    environment:
      MEMORY_FILE_PATH: /data/global.jsonl
    ports:
      - "${MCP_MEMORY_PORT:-22001}:3001"
    volumes:
      - ../data:/data
    networks:
      - df-network
    labels:
      managed-by: docker-framework
      df.type: project
      df.project: ${PROJECT_SLUG}

networks:
  df-network:
    name: df-network
    external: true
```

> **Nota sobre porta:** o framework não injeta `MCP_MEMORY_PORT` automaticamente para serviços de projeto (apenas para templates de infra). O valor `:-22001` é o fallback hardcoded que deve ser mantido em sincronia com os índices em `squads.yml` (squad 2, projeto 2 → 22001). Se os índices mudarem, este valor precisa ser atualizado manualmente.

---

## Atualização do squads.yml

Adicionar `mcp-memory` como projeto index 2 da squad `pm`:

```yaml
- index: 2
  slug: pm
  projects:
    - index: 1
      slug: obsidian
    - index: 2
      slug: mcp-memory
```

---

## Configuração MCP nos projetos

Cada projeto que quiser usar a memória adiciona ao seu `.claude/settings.json` ou `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "memory": {
      "url": "http://localhost:22001/sse"
    }
  }
}
```

### System prompt recomendado para organização por projeto

```
Follow this memory protocol:
- Each project has an entity of type "project-context" with the project slug as name
- Always associate memories to the relevant project entity
- Before storing a memory, check if a project-context entity exists; create it if not
- Use relations to link cross-project information when relevant
```

---

## Operação

```bash
# Iniciar (dentro de project-pm/mcp-memory)
df start

# Verificar status
df status

# Ver logs
df log mcp-memory -f

# Parar
df stop
```

O container tem `restart: unless-stopped`, portanto sobe automaticamente com o Docker daemon.

---

## Fora do escopo

- Múltiplos containers por projeto (descartado em favor de organização por entidade)
- Autenticação/autorização no endpoint SSE
- Interface web de visualização do grafo
