# mcp-memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o projeto `mcp-memory` na squad `pm` do docker-framework, disponibilizando o MCP Memory Server como container sempre ativo acessível via SSE na porta 22001.

**Architecture:** Um único container Node.js rodando `@modelcontextprotocol/server-memory` com transporte SSE, usando bind mount local para persistir o grafo de conhecimento em `data/global.jsonl`. O projeto segue as convenções do docker-framework: `df.yml` como manifesto, subdiretório `mcp-memory/` com `docker-compose.yml`, e registro no `config/squads.yml`.

**Tech Stack:** Docker, Node.js (node:lts-alpine), @modelcontextprotocol/server-memory (npx), YAML (yq), Bash (df CLI)

---

## Mapa de arquivos

| Ação | Arquivo | Responsabilidade |
|------|---------|-----------------|
| Modificar | `config/squads.yml` | Registrar mcp-memory como projeto index 2 da squad pm |
| Criar | `project-pm/mcp-memory/df.yml` | Manifesto do projeto (nome, squad, dependências) |
| Criar | `project-pm/mcp-memory/mcp-memory/docker-compose.yml` | Definição do container MCP Memory |
| Criar | `project-pm/mcp-memory/data/.gitkeep` | Manter diretório de dados no git (JSONL é gerado em runtime) |

---

## Task 1: Registrar mcp-memory no squads.yml

**Files:**
- Modify: `config/squads.yml`

- [ ] **Step 1: Abrir e verificar o estado atual do squads.yml**

```bash
cat /opt/docker-framework/config/squads.yml
```

Esperado: squad `pm` tem apenas `obsidian` (index 1). Não existe entry para `mcp-memory`.

- [ ] **Step 2: Adicionar mcp-memory como projeto index 2 da squad pm**

Editar `config/squads.yml`. A squad `pm` deve ficar assim:

```yaml
  - index: 2
    slug: pm
    projects:
      - index: 1
        slug: obsidian
      - index: 2
        slug: mcp-memory
```

- [ ] **Step 3: Verificar que o yq consegue ler o arquivo atualizado**

```bash
yq '.squads[] | select(.slug == "pm") | .projects' /opt/docker-framework/config/squads.yml
```

Esperado:
```yaml
- index: 1
  slug: obsidian
- index: 2
  slug: mcp-memory
```

- [ ] **Step 4: Verificar cálculo de porta esperado via lógica do framework**

O framework calcula a porta como `(squad_index * 10 + project_index) * 1000 + NNN`.
- squad `pm` = index 2
- projeto `mcp-memory` = index 2
- NNN = 001 (últimos 3 dígitos de 3001)
- Resultado: `(2*10+2)*1000 + 001 = 22001`

```bash
# Confirmar os índices no squads.yml
yq '.squads[] | select(.slug == "pm") | .index' /opt/docker-framework/config/squads.yml
yq '.squads[] | select(.slug == "pm") | .projects[] | select(.slug == "mcp-memory") | .index' /opt/docker-framework/config/squads.yml
```

Esperado: `2` e `2` respectivamente.

- [ ] **Step 5: Commit**

```bash
cd /opt/docker-framework
git add config/squads.yml
git commit -m "feat(config): register mcp-memory as project index 2 in pm squad"
```

---

## Task 2: Criar o manifesto df.yml

**Files:**
- Create: `project-pm/mcp-memory/df.yml`

- [ ] **Step 1: Verificar que o diretório project-pm/mcp-memory não existe ainda**

```bash
ls /opt/docker-framework/project-pm/
```

Esperado: apenas `obsidian` listado.

- [ ] **Step 2: Criar o diretório e o df.yml**

```bash
mkdir -p /opt/docker-framework/project-pm/mcp-memory
```

Criar `/opt/docker-framework/project-pm/mcp-memory/df.yml` com o conteúdo:

```yaml
project:
  name: mcp-memory
  squad: pm

dependencies:
  services:
    - mcp-memory
```

- [ ] **Step 3: Verificar que o framework consegue ler o manifesto**

```bash
cd /opt/docker-framework/project-pm/mcp-memory
yq '.project.name' df.yml
yq '.project.squad' df.yml
yq '.dependencies.services[]' df.yml
```

Esperado: `mcp-memory`, `pm`, `mcp-memory`.

- [ ] **Step 4: Verificar que o df consegue resolver o projeto (dry-run)**

```bash
cd /opt/docker-framework/project-pm/mcp-memory
df start --dry-run
```

Esperado: mensagem de dry-run mencionando o serviço `mcp-memory`. Pode falhar com "service directory not found" — isso é esperado pois o docker-compose.yml ainda não existe. O importante é que o manifesto seja lido sem erros de parse.

- [ ] **Step 5: Commit**

```bash
cd /opt/docker-framework
git add project-pm/mcp-memory/df.yml
git commit -m "feat(pm): add mcp-memory project manifest"
```

---

## Task 3: Criar o docker-compose.yml do serviço

**Files:**
- Create: `project-pm/mcp-memory/mcp-memory/docker-compose.yml`
- Create: `project-pm/mcp-memory/data/.gitkeep`

> **Convenção crítica:** o framework resolve o compose em `{app_dir}/{service_name}/docker-compose.yml`.
> Como o serviço se chama `mcp-memory` e o app_dir é `project-pm/mcp-memory`, o compose fica em
> `project-pm/mcp-memory/mcp-memory/docker-compose.yml`.

- [ ] **Step 1: Criar os diretórios necessários**

```bash
mkdir -p /opt/docker-framework/project-pm/mcp-memory/mcp-memory
mkdir -p /opt/docker-framework/project-pm/mcp-memory/data
```

- [ ] **Step 2: Criar o .gitkeep para o diretório de dados**

```bash
touch /opt/docker-framework/project-pm/mcp-memory/data/.gitkeep
```

O arquivo `global.jsonl` é criado automaticamente pelo servidor em runtime — não deve ser commitado.

- [ ] **Step 3: Criar o docker-compose.yml**

Criar `/opt/docker-framework/project-pm/mcp-memory/mcp-memory/docker-compose.yml`:

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

- [ ] **Step 4: Validar o docker-compose.yml com docker compose config**

```bash
cd /opt/docker-framework/project-pm/mcp-memory/mcp-memory
PROJECT_SLUG=mcp-memory docker compose -f docker-compose.yml config
```

Esperado: YAML expandido sem erros, com `container_name: mcp-memory`, porta `22001:3001`, volume `../data:/data`.

- [ ] **Step 5: Verificar o dry-run completo do df start**

```bash
cd /opt/docker-framework/project-pm/mcp-memory
df start --dry-run
```

Esperado: dry-run mencionando o serviço `mcp-memory` e o arquivo `mcp-memory/docker-compose.yml`. Sem erros de "service directory not found".

- [ ] **Step 6: Adicionar global.jsonl ao .gitignore**

Criar ou editar `/opt/docker-framework/project-pm/mcp-memory/.gitignore`:

```
data/global.jsonl
data/*.jsonl
```

- [ ] **Step 7: Commit**

```bash
cd /opt/docker-framework
git add project-pm/mcp-memory/mcp-memory/docker-compose.yml
git add project-pm/mcp-memory/data/.gitkeep
git add project-pm/mcp-memory/.gitignore
git commit -m "feat(pm): add mcp-memory docker-compose and data directory"
```

---

## Task 4: Subir o container e verificar funcionamento

- [ ] **Step 1: Garantir que a rede df-network existe**

```bash
docker network ls | grep df-network
```

Se não existir:
```bash
docker network create df-network
```

- [ ] **Step 2: Subir o container via df start**

```bash
cd /opt/docker-framework/project-pm/mcp-memory
df start
```

Esperado: container `mcp-memory` subindo, logs indicando servidor MCP inicializado.

- [ ] **Step 3: Verificar que o container está rodando**

```bash
df status
```

Esperado: `mcp-memory` com status `running`.

- [ ] **Step 4: Verificar logs do servidor**

```bash
df log mcp-memory -n 20
```

Esperado: logs do servidor MCP Memory inicializado, sem erros. Deve aparecer algo como `MCP Memory Server running` ou similar indicando que o SSE está ativo.

- [ ] **Step 5: Verificar que o endpoint SSE responde**

```bash
curl -v --max-time 5 http://localhost:22001/sse 2>&1 | head -20
```

Esperado: resposta HTTP 200 com `Content-Type: text/event-stream`. Pode ficar em streaming — Ctrl+C após confirmar o header.

- [ ] **Step 6: Verificar que o arquivo global.jsonl foi criado**

```bash
ls -la /opt/docker-framework/project-pm/mcp-memory/data/
```

Esperado: `global.jsonl` presente (pode estar vazio inicialmente).

- [ ] **Step 7: Parar e subir novamente para verificar persistência**

```bash
cd /opt/docker-framework/project-pm/mcp-memory
df stop
df start
curl -s --max-time 3 http://localhost:22001/sse > /dev/null && echo "SSE OK" || echo "SSE FAIL"
```

Esperado: `SSE OK` após reinicialização.

---

## Task 5: Documentar configuração MCP para projetos

**Files:**
- Create: `project-pm/mcp-memory/README.md`

- [ ] **Step 1: Criar README.md com instruções de uso**

Criar `/opt/docker-framework/project-pm/mcp-memory/README.md`:

```markdown
# mcp-memory

MCP Memory Server para o docker-framework. Disponibiliza memória persistente via grafo de conhecimento (JSONL) acessível por agentes Claude Code via SSE.

## Porta

`22001` (squad pm index 2, projeto index 2, base 3001)

## Iniciar

```bash
df start
```

## Configurar em projetos

Adicionar ao `.claude/settings.json` do projeto:

```json
{
  "mcpServers": {
    "memory": {
      "url": "http://localhost:22001/sse"
    }
  }
}
```

## System prompt recomendado

```
Follow this memory protocol:
- Each project has an entity of type "project-context" with the project slug as name
- Always associate memories to the relevant project entity
- Before storing a memory, check if a project-context entity exists; create it if not
- Use relations to link cross-project information when relevant
```

## Storage

Dados persistidos em `data/global.jsonl`. Backup incluído em `df backup`.

## Nota sobre porta

O valor `22001` está hardcoded no `docker-compose.yml` como fallback (`${MCP_MEMORY_PORT:-22001}`).
Se os índices em `config/squads.yml` mudarem, atualizar o valor no compose manualmente.
```

- [ ] **Step 2: Commit**

```bash
cd /opt/docker-framework
git add project-pm/mcp-memory/README.md
git commit -m "docs(pm): add mcp-memory usage README"
```

---

## Verificação final

- [ ] `df status` mostra `mcp-memory` como `running`
- [ ] `curl http://localhost:22001/sse` retorna `text/event-stream`
- [ ] `data/global.jsonl` existe no diretório de dados
- [ ] `config/squads.yml` contém `mcp-memory` com index 2 na squad `pm`
- [ ] `df stop && df start` sobe o container novamente sem erros
