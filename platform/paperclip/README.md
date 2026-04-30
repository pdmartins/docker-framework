# Paperclip

Painel de controle de agentes AI. Acesso: `https://paperclip.bewiser.com.br`
 
## Setup

```bash
cd /opt/docker-framework/platform/paperclip

# 1. Criar .env
cp .env.example .env

# 2. Preencher os valores no .env:
#    BETTER_AUTH_SECRET: openssl rand -hex 32
#    ANTHROPIC_API_KEY: chave da Anthropic
#    PAPERCLIP_UID/GID: resultado de "id palantir"

# 3. Build e subir
docker compose up -d --build
```

O build demora alguns minutos na primeira vez (compila UI + server em TypeScript).

## Estrutura

- **Build**: a partir do fonte em `./paperclip/` (git clone do repo oficial)
- **Traefik**: roteamento automático via labels, sem porta exposta no host
- **SSH**: `/home/saruman/.ssh` montado read-only em `/home/node/.ssh` para acesso a Erebor e Barad-dûr
- **Postgres 17**: container dedicado `platform-paperclip-db`, dados em `./volumes/postgresql`
- **App data**: persistido em `./volumes/data`

## Atualizar

```bash
cd /repos/_mv/paperclipai--paperclip
git pull

cd /opt/docker-framework/platform/paperclip
docker compose up -d --build
```

## Primeiro acesso

1. Abrir `https://paperclip.bewiser.com.br`
2. Criar conta board (primeiro usuário vira admin)
3. Criar as companies:
   - **BeWiser** (initiatives: Assistant, Agronomy, SkyBoards)
   - **HapVida** (initiative: STT)
   - **Sky** (initiative: Sky.HubAI)
   - **Iakan** (initiative: Iakan)
   - **PMartins** (initiatives: TokenGate, EasyScripts)

## Integrar OpenClaw (Saruman)

1. Paperclip UI → Settings da company → Invites
2. Clicar em **Generate OpenClaw Invite Prompt**
3. Copiar o prompt gerado
4. Colar no chat do Saruman (OpenClaw)
5. Aprovar o join request no Paperclip UI

## Integrar Claude Code (Erebor / Barad-dûr)

Usar adapter `process` com SSH no adapter config do agente:
- **Command**: `ssh palantir@erebor "cd /repos/<projeto> && claude --print ..."`
- O container tem acesso SSH via mount de `/home/palantir/.ssh`
