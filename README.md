# Docker Framework

CLI (`df`) em Bash para orquestração de ambientes Docker multi-projeto. Gerencia infra compartilhada (SQL Server, Kafka, Redis, etc.) e projetos isolados via git submodules.

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
├── infra/                   # Recursos de infraestrutura
│   ├── .config/
│   │   ├── ports.yml        # Portas de infra (source of truth)
│   │   └── credentials.yml  # Credenciais de infra (source of truth)
│   ├── sql_server/
│   ├── kafka/
│   ├── zookeeper/
│   ├── mongodb/
│   └── redis/
├── project-{team}/          # Submodules por equipe
│   ├── config/
│   │   ├── ports.yml        # Portas das apps deste projeto
│   │   └── credentials.yml  # Credenciais específicas (opcional)
│   └── {app}/
│       ├── df.yml           # Manifesto de dependências
│       ├── docker-compose.yml
│       └── init/            # Scripts de inicialização
└── .gitmodules
```

## Comandos

| Comando | Descrição |
|---------|-----------|
| `df start` | Sobe infra + projeto no diretório atual |
| `df stop` | Para o projeto (e infra sem uso com `--with-infra`) |
| `df restart` | Reinicia projeto e dependências |
| `df status` | Estado de todos os containers gerenciados |
| `df reset` | Limpa dados, re-init e reinicia |
| `df log [recurso]` | Exibe logs do projeto ou recurso específico |

## Uso Rápido

```bash
# Navegar até uma app de projeto
cd project-hv/autocid

# Subir tudo (infra + init scripts + app)
df start

# Ver status
df status

# Logs
df log              # logs da app
df log sql_server   # logs do SQL Server

# Parar
df stop
df stop --with-infra   # também para infra sem uso

# Reset completo (apaga dados, reinicializa)
df reset
```

## Infra Disponível

| Recurso | Porta | Imagem |
|---------|-------|--------|
| SQL Server | 1433 | mcr.microsoft.com/mssql/server:2022-latest |
| Kafka | 9092 | confluentinc/cp-kafka:7.6.0 |
| Zookeeper | 2181 | confluentinc/cp-zookeeper:7.6.0 |
| MongoDB | 27017 | mongo:7.0 |
| Redis | 6379 | redis:7-alpine |

## Conceitos-Chave

- **CLI como orquestrador** — `df` resolve lifecycle, docker-compose é building block
- **Infra singleton** — cada recurso roda UMA vez, compartilhado entre projetos
- **Isolamento lógico** — projetos compartilham containers mas têm databases/topics separados
- **Init scripts idempotentes** — cada projeto traz seus scripts (CREATE IF NOT EXISTS)
- **Submodules por equipe** — cada `project-{team}/` é um repo separado
- **Zero hardcode** — portas e credenciais NUNCA nos docker-compose ou scripts, sempre dos config YAMLs
- **Config por escopo** — infra em `infra/.config/` (compartilhada), projetos em `{projeto}/config/`
- **.env gerado** — CLI lê YAMLs e gera `.env` antes de rodar compose

## Licença

MIT
