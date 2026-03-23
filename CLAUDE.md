# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é este projeto

**Docker Framework** é uma CLI (`df`) em Bash para orquestração de ambientes Docker multi-projeto. Gerencia três camadas de serviços:
- **Plataforma** — serviços compartilhados singleton (ex: SonarQube em `platform/`)
- **Infra** — serviços isolados por projeto com portas calculadas automaticamente (PostgreSQL, Kafka, Redis, etc.)
- **Serviços** — containers docker-compose do próprio projeto

## Comandos principais

```bash
# Uso geral (executar dentro de project-{team}/{app})
df start              # sobe plataforma + infra + init scripts + app
df start --no-init    # idem sem rodar init scripts
df stop               # para projeto e infra (plataforma fica rodando)
df restart            # reinicia projeto e dependências
df status             # estado de todos containers gerenciados
df reset              # limpa dados, re-init e reinicia
df reset --force      # sem confirmação interativa
df log <serviço> [-f] [-n N]  # logs de container específico
df backup             # backup de volumes Docker para ZIP
df restore            # restaura volumes de backup
df nuke               # limpa recursos Docker (soft prune ou hard reset)
df platform start|stop|status  # gerencia plataforma compartilhada
```

## Arquitetura

### Entry point e despacho de comandos

`bin/df` define vars globais (`ROOT_DIR`, `LIB_DIR`, `TEMPLATES_DIR`, `PLATFORM_DIR`, `CONFIG_DIR`), faz `source` de todos os módulos e despacha para `cmd_<comando>()`.

### Módulos (`lib/`)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `core.sh` | Logging, helpers Docker, validação de pré-requisitos |
| `config.sh` | Leitura de YAML (`yq`), cálculo de portas, geração de `.env` temporário |
| `deps.sh` | Resolução de dependências declaradas no `df.yml` |
| `infra.sh` | Gerência do ciclo de vida dos containers de infra por projeto |
| `init.sh` | Execução de init scripts dentro dos containers (PostgreSQL, Kafka, Redis, etc.) |
| `commands/*.sh` | Um arquivo por comando; cada um exporta `cmd_<nome>()` |

### Convenção de nomes de containers

- Projeto: `{PROJECT_SLUG}`
- Infra: `infra-{PROJECT_SLUG}-{SERVICE}`
- Plataforma: `platform-{SERVICE}`

Todos os containers recebem labels `managed-by=docker-framework` e `df.type=platform|infra|project`.

### Cálculo de portas (zero hardcode)

Fórmula: `(squad_index * 10 + project_index) * 1000 + NNN`
`NNN` = últimos 3 dígitos da porta padrão do serviço.

**Source of truth:** `config/squads.yml` — mapeia squad → index e project → index.

Exemplo: squad 2, projeto 1, PostgreSQL → `(2*10+1)*1000 + 432 = 21432`

O `.env` com as portas calculadas é gerado em diretório temporário antes de cada `docker compose` e descartado depois.

### Manifesto `df.yml`

Cada app declara suas dependências:

```yaml
project:
  name: my-app      # slug único
  squad: my-team    # slug da squad (deve existir em config/squads.yml)

dependencies:
  infra:            # templates/ — isolados por projeto
    - postgresql
    - redis
  platform:         # platform/ — compartilhados
    - sonarqube
  services:         # docker-compose local da app
    - api
    - worker
```

### Submodules por equipe

Cada `project-{team}/` é um repositório Git separado linkado como submodule. Ao adicionar projetos, atualizar `config/squads.yml` e registrar o submodule correspondente.

### Init scripts

Scripts em `project-{team}/{app}/init/` são executados dentro dos containers a cada `df start` (idempotentes por design — usar `CREATE IF NOT EXISTS`, etc.). São despachados por `lib/init.sh` com handlers específicos por tipo de serviço.

### Rede Docker

Todos os containers compartilham a rede `df-network`, criada sob demanda por `ensure_network()` em `lib/core.sh`.

## Pré-requisitos

- Docker + Docker Compose
- `yq` (parser YAML — obrigatório para leitura de df.yml e squads.yml)
- Bash 4+
- Git

## Adicionando novo serviço de infra

1. Criar `templates/{service}/docker-compose.yml` (usar variáveis de ambiente para portas)
2. Adicionar handler de porta em `lib/config.sh`
3. Adicionar handler de init (se necessário) em `lib/init.sh`
4. Documentar no README.md

## Adicionando novo serviço de plataforma

1. Criar `platform/{service}/docker-compose.yml` com label `df.type=platform`
2. Registrar no handler `cmd_platform()` em `lib/commands/platform.sh`
