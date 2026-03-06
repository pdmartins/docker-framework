# Docker Framework

CLI (`df`) em Bash para orquestração de ambientes Docker multi-projeto. Gerencia infra por projeto (PostgreSQL, Kafka, Redis, etc.) e plataforma compartilhada via git submodules.

## Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) + Docker Compose
- [yq](https://github.com/mikefarah/yq) (parser YAML)
- Bash 4+
- Git

## Instalação

```bash
# Clone o repositório
git clone https://github.com/pdmartins/docker-framework.git
cd docker-framework

# Inicializar submodules
git submodule update --init --recursive

# Adicionar ao PATH
echo 'export PATH="$HOME/docker-framework/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verificar instalação
df --version
```

## Estrutura

```
docker-framework/
├── bin/df                   # CLI entrypoint
├── lib/                     # Funções modulares do CLI
│   ├── core.sh              # Log, validação, helpers
│   ├── config.sh            # Leitura YAML + geração de .env
│   ├── deps.sh              # Resolução de dependências
│   ├── infra.sh             # Gerência de containers de infra
│   ├── init.sh              # Execução de init scripts
│   └── commands/            # Um arquivo por comando
│       ├── start.sh
│       ├── stop.sh
│       ├── restart.sh
│       ├── status.sh
│       ├── reset.sh
│       └── log.sh
├── config/
│   └── squads.yml           # Registro de squads e projetos (source of truth)
├── templates/               # docker-compose templates por serviço de infra
│   ├── kafka/
│   ├── postgresql/
│   ├── rabbitmq/
│   ├── redis/
│   └── zookeeper/
├── platform/                # Serviços compartilhados (não por projeto)
│   └── sonarqube/
├── project-{team}/          # Submodules por equipe
│   └── {app}/
│       ├── df.yml           # Manifesto de dependências
│       ├── docker-compose.yml
│       └── init/            # Scripts de inicialização (idempotentes)
└── .gitmodules
```

## Comandos

| Comando | Descrição |
|---------|-----------|
| `df start [--no-init]` | Sobe plataforma + infra + projeto no diretório atual |
| `df stop` | Para o projeto e a infra (plataforma permanece) |
| `df restart` | Reinicia projeto e dependências |
| `df status` | Estado de todos os containers gerenciados |
| `df reset [-f]` | Limpa dados, re-init e reinicia |
| `df log <serviço> [-f] [-n N]` | Exibe logs do serviço especificado |

## Uso Rápido

```bash
# Navegar até uma app de projeto
cd project-{team}/{app}

# Subir tudo (plataforma + infra + init scripts + app)
df start

# Subir sem rodar init scripts
df start --no-init

# Ver status
df status

# Logs
df log postgresql          # logs do PostgreSQL deste projeto
df log sonarqube           # logs do SonarQube (plataforma)
df log kafka -f            # follow logs do Kafka
df log redis -n 50         # últimas 50 linhas do Redis

# Parar
df stop                    # para projeto e infra (plataforma fica rodando)

# Reset completo (apaga dados, reinicializa)
df reset
df reset --force           # sem confirmação interativa
```

## Infra Disponível

Serviços disponíveis via `templates/` (por projeto, isolados):

| Recurso | Porta padrão | Template |
|---------|-------------|----------|
| PostgreSQL | 5432 | `templates/postgresql/` |
| Kafka | 9092 | `templates/kafka/` |
| Zookeeper | 2181 | `templates/zookeeper/` |
| Redis | 6379 | `templates/redis/` |
| RabbitMQ | 5672 | `templates/rabbitmq/` |

Serviços disponíveis via `platform/` (compartilhados, sem isolamento):

| Recurso | Template |
|---------|----------|
| SonarQube | `platform/sonarqube/` |

## Conceitos-Chave

- **CLI como orquestrador** — `df` resolve lifecycle, docker-compose é building block
- **Infra isolada por projeto** — cada projeto tem containers próprios (nomeados `infra-{slug}-{service}`) com portas calculadas automaticamente via `config/squads.yml`
- **Plataforma compartilhada** — serviços em `platform/` são singleton, compartilhados entre todos os projetos (ex: SonarQube)
- **Init scripts idempotentes** — cada projeto traz scripts em `init/` executados dentro dos containers (CREATE IF NOT EXISTS)
- **Submodules por equipe** — cada `project-{team}/` é um repo separado
- **Zero hardcode** — portas nunca nos docker-compose, calculadas a partir de `config/squads.yml`
- **.env gerado em temp** — CLI calcula portas e escreve `.env` temporário antes de rodar compose

## Manifesto df.yml

Cada app deve ter um `df.yml` na raiz do seu diretório:

```yaml
project:
  name: my-app        # slug único da app
  squad: my-team      # slug da squad (deve existir em config/squads.yml)

dependencies:
  infra:              # serviços de infra isolados por projeto
    - postgresql
    - redis
  platform:           # serviços compartilhados (platform/)
    - sonarqube
  services:           # serviços docker-compose locais da própria app
    - api
    - worker
```

Serviços disponíveis para `infra`: `postgresql`, `kafka`, `zookeeper`, `redis`, `rabbitmq`.  
Serviços disponíveis para `platform`: `sonarqube`.

## Squads Registry

O arquivo `config/squads.yml` é o source of truth para o cálculo de portas:

```yaml
squads:
  - index: 1          # X na fórmula de porta (XY * 1000 + NNN)
    slug: my-team
    projects:
      - index: 1      # Y na fórmula de porta
        slug: my-app
```

Fórmula de porta: `(squad_index * 10 + project_index) * 1000 + NNN`  
Onde `NNN` são os últimos 3 dígitos da porta padrão do serviço (ex: PostgreSQL → 432).

Exemplo: squad 1, projeto 1, PostgreSQL → `11 * 1000 + 432 = 11432`.

## Licença

MIT
