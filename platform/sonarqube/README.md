# SonarQube — Platform Service

Serviço compartilhado de análise estática de código. Roda como plataforma do docker-framework (não está atrelado a nenhum projeto específico) e fica disponível para todos os repositórios do ambiente.

- **URL**: http://localhost:9000
- **Imagem**: `sonarqube:26.3.0.120487-community`
- **Containers**: `platform-sonarqube`, `platform-sonarqube-db` (PostgreSQL 16)
- **Rede**: `df-network` (compartilhada com todos os projetos)

---

## Pré-requisitos

### Parâmetro do kernel (Linux / WSL)

O SonarQube requer `vm.max_map_count >= 524288`. Verifique e ajuste se necessário:

```bash
# Verificar valor atual
sysctl vm.max_map_count

# Aplicar temporariamente (reseta ao reiniciar)
sudo sysctl -w vm.max_map_count=524288

# Aplicar permanentemente
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

> **WSL**: adicione no arquivo `%USERPROFILE%\.wsdconfig`:
> ```ini
> [wsl2]
> kernelCommandLine = sysctl.vm.max_map_count=524288
> ```

### Diretórios de volume

Os volumes usam bind mount. Crie os diretórios antes de subir o container pela primeira vez:

```bash
mkdir -p platform/sonarqube/volumes/{data,logs,extensions,postgresql}
```

---

## Subindo o SonarQube

### Via docker-framework CLI

```bash
# A partir da raiz do docker-framework
df start sonarqube
```

### Diretamente com Docker Compose

```bash
cd platform/sonarqube
docker compose up -d
```

Para acompanhar os logs durante a inicialização (pode levar ~2 minutos):

```bash
docker logs -f platform-sonarqube
```

O container estará pronto quando o healthcheck responder `"status":"UP"`:

```bash
docker inspect --format='{{.State.Health.Status}}' platform-sonarqube
# healthy
```

---

## Primeiro acesso

1. Acesse http://localhost:9000
2. Faça login com as credenciais padrão:
   - **Usuário**: `admin`
   - **Senha**: `admin`
3. O sistema pedirá para trocar a senha — defina uma senha segura

---

## Configuração inicial (uma vez)

### 1. Criar um projeto

1. Clique em **Create Project > Manually**
2. Defina:
   - **Project key**: identificador único (ex: `meu-squad-minha-api`)
   - **Display name**: nome legível
3. Clique em **Set Up**

### 2. Gerar um token de análise

1. Em **How do you want to analyze your repository?**, escolha **Locally**
2. Em **Provide a token**, clique em **Generate**
3. Copie o token gerado — ele só aparece uma vez

> Tokens também podem ser gerenciados em **My Account > Security > Generate Tokens**.

---

## Plugando um repositório para análise

### Opção A — Maven

Adicione ao `pom.xml` (ou passe via linha de comando):

```xml
<properties>
  <sonar.host.url>http://localhost:9000</sonar.host.url>
  <sonar.projectKey>meu-squad-minha-api</sonar.projectKey>
</properties>
```

Execute a análise:

```bash
mvn verify sonar:sonar -Dsonar.token=<TOKEN>
```

### Opção B — Gradle

```bash
./gradlew sonar \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.projectKey=meu-squad-minha-api \
  -Dsonar.token=<TOKEN>
```

### Opção C — .NET (dotnet sonarscanner)

Instale o scanner globalmente (uma vez):

```bash
dotnet tool install --global dotnet-sonarscanner
```

Fluxo de análise:

```bash
# 1. Início — configura a análise
dotnet sonarscanner begin \
  /k:"meu-squad-minha-api" \
  /d:sonar.host.url="http://localhost:9000" \
  /d:sonar.token="<TOKEN>"

# 2. Build normal do projeto
dotnet build

# 3. Testes com cobertura (opcional mas recomendado)
dotnet test --collect:"XPlat Code Coverage"

# 4. Fim — envia resultados ao servidor
dotnet sonarscanner end /d:sonar.token="<TOKEN>"
```

Para incluir cobertura no resultado:

```bash
dotnet sonarscanner begin \
  /k:"meu-squad-minha-api" \
  /d:sonar.host.url="http://localhost:9000" \
  /d:sonar.token="<TOKEN>" \
  /d:sonar.cs.opencover.reportsPaths="**/coverage.opencover.xml"
```

### Opção D — Sonar Scanner CLI

Instale o [Sonar Scanner](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/scanners/sonarscanner/) e crie o arquivo `sonar-project.properties` na raiz do repositório:

```properties
sonar.host.url=http://localhost:9000
sonar.projectKey=meu-squad-minha-api
sonar.projectName=Minha API
sonar.sources=src
sonar.exclusions=**/test/**,**/*.spec.*
```

Execute:

```bash
sonar-scanner -Dsonar.token=<TOKEN>
```

### Opção E — GitHub Actions / Pipeline CI

```yaml
- name: SonarQube Analysis
  uses: sonarsource/sonarqube-scan-action@master
  with:
    projectBaseDir: .
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: http://<IP_DO_SERVIDOR>:9000
```

> Em pipelines CI que rodam fora da rede Docker, use o IP do servidor (não `localhost`).

---

## Parando o serviço

```bash
# Via docker-framework
df stop sonarqube

# Direto
cd platform/sonarqube
docker compose down
```

Os dados persistem nos volumes — nenhuma configuração ou análise histórica é perdida.

---

## Estrutura de volumes

| Volume | Caminho no host | Conteúdo |
|--------|----------------|----------|
| `platform-sonarqube-data` | `platform/sonarqube/volumes/data` | Índices Elasticsearch, configurações |
| `platform-sonarqube-logs` | `platform/sonarqube/volumes/logs` | Logs da aplicação |
| `platform-sonarqube-extensions` | `platform/sonarqube/volumes/extensions` | Plugins instalados |
| `platform-sonarqube-postgresql` | `platform/sonarqube/volumes/postgresql` | Banco de dados PostgreSQL |

---

---

## SonarQube for IDE (VS Code)

A extensão [SonarQube for IDE](https://marketplace.visualstudio.com/items?itemName=SonarSource.sonarlint-vscode) (SonarLint) permite análise em tempo real no editor, sincronizando as regras do servidor local.

### Diferença entre SonarLint e sonarscanner

| | SonarLint (extensão) | sonarscanner |
|---|---|---|
| Roda quando | Conforme você digita | Manualmente ou no CI |
| Atualiza dashboard | Não | Sim |
| Cobertura de testes | Não | Sim |
| Verifica Quality Gate | Não | Sim |
| Uso típico | Feedback imediato no editor | Análise completa antes do PR / no CI |

Os dois se complementam: o SonarLint detecta issues enquanto você codifica, o sonarscanner faz a análise oficial.

### Configuração

**1. Gerar token no SonarQube**

- Acesse http://localhost:9000 → Administration → Security → Users → seu usuário → Tokens
- Crie um token do tipo **User Token** e copie o valor

**2. Adicionar a conexão no VS Code**

Paleta (`Ctrl+Shift+P`) → `SonarQube: Add SonarQube Connection`, ou adicione ao `settings.json`:

```json
"sonarlint.connectedMode.connections.sonarqube": [
  {
    "connectionId": "local",
    "serverUrl": "http://localhost:9000",
    "token": "<seu-token>"
  }
]
```

**3. Vincular o workspace ao projeto**

No `.vscode/settings.json` do repositório:

```json
"sonarlint.connectedMode.project": {
  "connectionId": "local",
  "projectKey": "meu-squad-minha-api"
}
```

**4. Sincronizar regras**

`Ctrl+Shift+P` → `SonarQube: Update All Project Bindings`

Isso baixa as Quality Profiles do servidor, garantindo que o editor use as mesmas regras do CI.

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---------|---------------|--------|
| Container reinicia em loop | `vm.max_map_count` baixo | Ajustar parâmetro do kernel (ver Pré-requisitos) |
| `Waiting for Elasticsearch...` por mais de 5 min | Permissão nos diretórios de volume | `chmod -R 777 platform/sonarqube/volumes/` |
| Erro 502 / página em branco | Container ainda inicializando | Aguardar healthcheck ficar `healthy` |
| `platform-sonarqube` fica em `Created` sem subir | Postgres ainda não estava healthy | `docker start platform-sonarqube` |
| Token inválido na análise | Token expirado ou copiado errado | Gerar novo token em **My Account > Security** |
