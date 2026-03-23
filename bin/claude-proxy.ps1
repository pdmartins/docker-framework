# claude-proxy.ps1 — Toggle Claude Code entre copilot-api e Anthropic direto
#
# Uso:
#   claude-proxy.ps1 enable   # Aponta Claude Code para copilot-api em orthanc.bewiser.com.br
#   claude-proxy.ps1 disable  # Volta para Anthropic direto (OAuth/API key)
#   claude-proxy.ps1 status   # Exibe modo atual e verifica conectividade com o servidor
#   claude-proxy.ps1 auth     # Instruções para autenticar o copilot-api no servidor
#
# Nota: o container copilot-api roda em Orthanc (Linux). Este script apenas
#       configura o Claude Code local para usar o proxy remoto.

param(
    [Parameter(Position = 0)]
    [string]$Command = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Configuração ---
$COPILOT_API_URL   = "http://orthanc.bewiser.com.br:4141"
$CLAUDE_SETTINGS   = "$env:APPDATA\Claude\settings.json"
$REMOTE_HOST       = "orthanc.bewiser.com.br"
$REMOTE_PORT       = 4141

# Configurações injetadas no settings.json do Claude Code ao ativar o proxy.
# Ajuste os modelos conforme os disponíveis no seu GitHub Copilot.
$COPILOT_ENV_BLOCK = [ordered]@{
    ANTHROPIC_BASE_URL               = $COPILOT_API_URL
    ANTHROPIC_AUTH_TOKEN             = "dummy"
    ANTHROPIC_MODEL                  = "gpt-4.1"
    ANTHROPIC_DEFAULT_SONNET_MODEL   = "gpt-4.1"
    ANTHROPIC_SMALL_FAST_MODEL       = "gpt-4.1"
    ANTHROPIC_DEFAULT_HAIKU_MODEL    = "gpt-4.1"
    DISABLE_NON_ESSENTIAL_MODEL_CALLS          = "1"
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC   = "1"
}

# --- Helpers de cor ---
function Write-Info    { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "  $msg" -ForegroundColor Red }
function Write-Bold    { param($msg) Write-Host $msg -ForegroundColor White }

# --- Helpers de settings.json ---
function Get-ClaudeSettings {
    if (-not (Test-Path $CLAUDE_SETTINGS)) {
        return [PSCustomObject]@{}
    }
    try {
        Get-Content $CLAUDE_SETTINGS -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Falha ao ler ${CLAUDE_SETTINGS}: $_"
        exit 1
    }
}

function Save-ClaudeSettings {
    param([PSCustomObject]$settings)
    $dir = Split-Path $CLAUDE_SETTINGS
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $CLAUDE_SETTINGS -Encoding UTF8
}

function Get-ApiUrl {
    $s = Get-ClaudeSettings
    if ($s.PSObject.Properties["env"] -and $s.env.PSObject.Properties["ANTHROPIC_BASE_URL"]) {
        $s.env.ANTHROPIC_BASE_URL
    } else { "" }
}

function Set-ApiUrl {
    $s = Get-ClaudeSettings
    $s | Add-Member -MemberType NoteProperty -Name "env" -Value $COPILOT_ENV_BLOCK -Force
    Save-ClaudeSettings $s
}

function Remove-ApiUrl {
    $s = Get-ClaudeSettings
    if ($s.PSObject.Properties["env"]) {
        $s.PSObject.Properties.Remove("env")
        Save-ClaudeSettings $s
    }
}

# --- Verifica conectividade HTTP com o servidor ---
function Test-CopilotApi {
    param([string]$url)
    try {
        $null = Invoke-WebRequest -Uri $url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# --- Comandos ---
function Invoke-Enable {
    Write-Bold "Ativando modo copilot-api..."
    Write-Host ""

    Write-Info "Injetando env no Claude Code..."
    Set-ApiUrl

    Write-Host ""
    Write-Ok "v Modo copilot-api ativo"
    Write-Host "  Claude Code agora usa: $COPILOT_API_URL (GitHub Copilot)" -ForegroundColor White
    Write-Host "  Para reverter: .\claude-proxy.ps1 disable" -ForegroundColor Gray
}

function Invoke-Disable {
    Write-Bold "Desativando modo copilot-api..."
    Write-Host ""

    $current = Get-ApiUrl
    if ($current -ne "") {
        Write-Info "Removendo env de $CLAUDE_SETTINGS ..."
        Remove-ApiUrl
    } else {
        Write-Warn "env nao configurado (ja em modo direto)"
    }

    Write-Host ""
    Write-Ok "v Modo Anthropic direto ativo"
    Write-Host "  Claude Code agora usa: Anthropic direto (OAuth / API key)" -ForegroundColor White
    Write-Host "  Para ativar copilot-api: .\claude-proxy.ps1 enable" -ForegroundColor Gray
}

function Invoke-Status {
    Write-Bold "=== Claude Code - Modo de Conexao ==="
    Write-Host ""

    $apiUrl = Get-ApiUrl
    if ($apiUrl -ne "") {
        Write-Host "  Modo:  " -NoNewline; Write-Host "proxy" -ForegroundColor Yellow
        Write-Host "  URL:   $apiUrl"
    } else {
        Write-Host "  Modo:  " -NoNewline; Write-Host "direto (Anthropic)" -ForegroundColor Green
        Write-Host "  URL:   https://api.anthropic.com (padrao)"
    }

    if ($apiUrl -ne "") {
        Write-Host ""
        Write-Bold "=== Servidor ==="
        Write-Host ""

        if (Test-CopilotApi $apiUrl) {
            Write-Ok "v Servidor respondeu"
        } else {
            Write-Err "x Servidor nao respondeu em $apiUrl"
            Write-Host ""
            Write-Err "! AVISO: Claude Code aponta para o proxy mas o servidor nao responde!"
            Write-Warn "  Execute .\claude-proxy.ps1 disable para reverter para Anthropic direto."
            Write-Host ""
        }
    }
}

function Invoke-Auth {
    Write-Bold "Autenticacao do copilot-api"
    Write-Host ""
    Write-Warn "A autenticacao e gerenciada pelo servidor Orthanc, nao por esta maquina."
    Write-Host ""
    Write-Host "  Para autenticar, conecte-se ao servidor e execute:" -ForegroundColor White
    Write-Host ""
    Write-Host "    ssh orthanc" -ForegroundColor Cyan
    Write-Host "    claude-proxy auth        # OAuth interativo" -ForegroundColor Cyan
    Write-Host "    # ou" -ForegroundColor Gray
    Write-Host "    GH_TOKEN=ghp_... claude-proxy enable   # Personal Access Token" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Usage {
    Write-Host ""
    Write-Bold "claude-proxy.ps1 - Alterna Claude Code entre copilot-api e Anthropic direto"
    Write-Host ""
    Write-Host "Uso:" -ForegroundColor White
    Write-Host "  .\claude-proxy.ps1 <comando>"
    Write-Host ""
    Write-Host "Comandos:" -ForegroundColor White
    Write-Host "  enable    Aponta Claude Code para $COPILOT_API_URL"
    Write-Host "  disable   Reverte Claude Code para Anthropic direto"
    Write-Host "  status    Exibe modo atual e verifica conectividade com o servidor"
    Write-Host "  auth      Instrucoes para autenticar o copilot-api em Orthanc"
    Write-Host ""
    Write-Host "Exemplos:" -ForegroundColor White
    Write-Host "  .\claude-proxy.ps1 enable"
    Write-Host "  .\claude-proxy.ps1 status"
    Write-Host ""
}

# --- Main ---
switch ($Command.ToLower()) {
    "enable"          { Invoke-Enable }
    "disable"         { Invoke-Disable }
    "status"          { Invoke-Status }
    "auth"            { Invoke-Auth }
    { $_ -in "-h", "--help" } { Show-Usage }
    ""                { Show-Usage }
    default {
        Write-Host "Comando desconhecido: $Command" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
