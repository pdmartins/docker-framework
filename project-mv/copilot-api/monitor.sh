#!/usr/bin/env bash
# monitor.sh — Dashboard TUI em tempo real para copilot-api (estilo btop)
# Uso: ./monitor.sh [intervalo_segundos]
# Dependências: bash, curl, jq, tput

set -euo pipefail

# ─── Configuração ────────────────────────────────────────────────────────────

API_URL="${COPILOT_API_URL:-http://localhost:4141}"
INTERVAL="${1:-5}"

if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || [[ "${INTERVAL}" -lt 1 ]]; then
    echo "Uso: $0 [intervalo_segundos]" >&2
    exit 1
fi

# ─── Cores (256 colors, estilo btop) ─────────────────────────────────────────

C_BORDER=$'\033[38;5;240m'      # cinza escuro — bordas dos painéis
C_TITLE=$'\033[38;5;75m'        # azul claro — títulos dos painéis
C_HEADER=$'\033[38;5;69m'       # azul médio — cabeçalho principal
C_GREEN=$'\033[38;5;82m'        # verde btop — >50%
C_YELLOW=$'\033[38;5;226m'      # amarelo btop — 10-50%
C_RED=$'\033[38;5;196m'         # vermelho btop — <10% / overage
C_MAGENTA=$'\033[38;5;141m'     # roxo/magenta — unlimited
C_CYAN=$'\033[38;5;87m'         # ciano — labels e valores
C_WHITE=$'\033[38;5;255m'       # branco — valores primários
C_DIM=$'\033[2m'                # dim — texto secundário
C_BOLD=$'\033[1m'               # bold
C_RESET=$'\033[0m'              # reset

# ─── Verificação de dependências ─────────────────────────────────────────────

check_deps() {
    local missing=()
    for cmd in curl jq tput; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Erro: dependências faltando: ${missing[*]}" >&2
        echo "Instale com: apt-get install ${missing[*]}" >&2
        exit 1
    fi
}

# ─── Fetch ───────────────────────────────────────────────────────────────────

fetch_usage() {
    curl -sf --max-time 3 "${API_URL}/usage" 2>/dev/null
}

# ─── Utilitários de painel (estilo btop) ─────────────────────────────────────

# Largura total dos painéis (com margem lateral)
panel_width() {
    local cols
    cols="$(tput cols 2>/dev/null || echo 80)"
    local w=$(( cols - 4 ))
    [[ $w -lt 40 ]] && w=40
    [[ $w -gt 100 ]] && w=100
    echo "$w"
}

# Imprime borda superior: ┌─ Título ──────────────────────┐
draw_panel_top() {
    local title="$1"
    local width="$2"
    # título + 2 espaços + "─ " + "─┐" = title_len + 4 + 2 = title_len + 6
    local title_visible="${title}"
    local title_len=${#title_visible}
    local fill=$(( width - title_len - 4 ))  # "┌─ " + title + " " + fill + "┐"
    [[ $fill -lt 0 ]] && fill=0
    local dashes
    dashes="$(printf '─%.0s' $(seq 1 $fill))"
    printf '%s┌─ %s%s %s%s─%s┐%s\n' \
        "${C_BORDER}" "${C_TITLE}${C_BOLD}" "${title}" "${C_RESET}" "${C_BORDER}" "${dashes}" "${C_RESET}"
}

# Imprime borda inferior: └──────────────────────────────┘
draw_panel_bottom() {
    local width="$1"
    local dashes
    dashes="$(printf '─%.0s' $(seq 1 $(( width - 2 ))))"
    printf '%s└%s┘%s\n' "${C_BORDER}" "${dashes}" "${C_RESET}"
}

# Imprime linha de conteúdo: │ conteúdo (com padding) │
# $1 = conteúdo já formatado com escape codes
# $2 = largura do painel
# $3 = comprimento visível do conteúdo (sem escape codes)
draw_panel_row() {
    local content="$1"
    local width="$2"
    local visible_len="${3:-0}"
    local inner=$(( width - 4 ))  # "│ " + inner + " │"
    local pad=$(( inner - visible_len ))
    [[ $pad -lt 0 ]] && pad=0
    local spaces
    spaces="$(printf ' %.0s' $(seq 1 $pad))"
    printf '%s│%s  %s%s  %s│%s\n' \
        "${C_BORDER}" "${C_RESET}" "${content}" "${spaces}" "${C_BORDER}" "${C_RESET}"
}

draw_panel_empty_row() {
    local width="$1"
    draw_panel_row "" "$width" 0
}

# ─── Barras de progresso ──────────────────────────────────────────────────────

# Blocos graduados: 8 sub-blocos por caractere (estilo btop)
BAR_BLOCKS=('▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')

# render_gradient_bar <percent_float> <width> <color>
# Retorna a string da barra via stdout
render_gradient_bar() {
    local pct_raw="$1"
    local width="$2"
    local color="$3"

    # Converte para inteiro (0-100), clampando
    local pct
    pct=$(echo "$pct_raw" | awk '{v=$1; if(v<0) v=0; if(v>100) v=100; printf "%d", v}')

    # Número de blocos cheios e fração
    local filled=$(( pct * width / 100 ))
    local remainder=$(( (pct * width * 8 / 100) - (filled * 8) ))
    [[ $filled -gt $width ]] && filled=$width

    local bar=""
    # Blocos cheios
    if [[ $filled -gt 0 ]]; then
        bar+="${color}"
        local i
        for (( i=0; i<filled; i++ )); do
            bar+="█"
        done
        bar+="${C_RESET}"
    fi
    # Bloco parcial
    if [[ $filled -lt $width && $remainder -gt 0 ]]; then
        bar+="${color}${BAR_BLOCKS[$remainder - 1]}${C_RESET}"
        filled=$(( filled + 1 ))
    fi
    # Espaços vazios
    local empty=$(( width - filled ))
    if [[ $empty -gt 0 ]]; then
        bar+="${C_DIM}"
        local i
        for (( i=0; i<empty; i++ )); do
            bar+="░"
        done
        bar+="${C_RESET}"
    fi

    echo "$bar"
}

# render_unlimited_bar <width>
render_unlimited_bar() {
    local width="$1"
    local bar="${C_MAGENTA}"
    local i
    for (( i=0; i<width; i++ )); do
        bar+="█"
    done
    bar+="${C_RESET}"
    echo "$bar"
}

# Escolhe cor baseado no percentual
bar_color() {
    local pct_raw="$1"
    local pct
    pct=$(echo "$pct_raw" | awk '{printf "%d", $1}')
    if [[ $pct -lt 0 ]]; then
        echo "${C_RED}"
    elif [[ $pct -lt 10 ]]; then
        echo "${C_RED}"
    elif [[ $pct -lt 50 ]]; then
        echo "${C_YELLOW}"
    else
        echo "${C_GREEN}"
    fi
}

# ─── Utilitários de formatação ────────────────────────────────────────────────

format_reset_date() {
    local iso="$1"
    local date_part="${iso%%T*}"
    local days_remaining=""
    if command -v date &>/dev/null; then
        local now_ts target_ts
        now_ts=$(date +%s 2>/dev/null || echo 0)
        target_ts=$(date -d "${date_part}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${date_part}" +%s 2>/dev/null || echo 0)
        if [[ $target_ts -gt 0 && $now_ts -gt 0 ]]; then
            local diff=$(( (target_ts - now_ts) / 86400 ))
            days_remaining=" (${diff} dias)"
        fi
    fi
    echo "${date_part}${days_remaining}"
}

# Formata nome da quota para exibição
quota_display_name() {
    case "$1" in
        chat) echo "Chat" ;;
        completions) echo "Completions" ;;
        premium_interactions) echo "Premium Interactions" ;;
        *) echo "$1" ;;
    esac
}

# ─── Renderização de painéis ──────────────────────────────────────────────────

render_info_panel() {
    local json="$1"
    local width="$2"

    local login plan reset_date chat_enabled mcp_enabled copilotignore
    login=$(echo "$json" | jq -r '.login // "N/A"')
    plan=$(echo "$json" | jq -r '.copilot_plan // "N/A"')
    reset_date=$(echo "$json" | jq -r '.quota_reset_date_utc // ""')
    chat_enabled=$(echo "$json" | jq -r '.chat_enabled // false')
    mcp_enabled=$(echo "$json" | jq -r '.is_mcp_enabled // false')
    copilotignore=$(echo "$json" | jq -r '.copilotignore_enabled // false')

    local reset_fmt
    reset_fmt=$(format_reset_date "$reset_date")

    local inner=$(( width - 4 ))

    draw_panel_top "Conta" "$width"

    # Linha: Usuário + Plano
    local user_label="${C_DIM}Usuário${C_RESET}  ${C_BOLD}${C_WHITE}${login}${C_RESET}"
    local plan_label="${C_DIM}Plano${C_RESET}  ${C_CYAN}${plan}${C_RESET}"
    local user_vis_len=$(( ${#login} + 9 ))   # "Usuário  " = 9 chars
    local plan_vis_len=$(( ${#plan} + 7 ))     # "Plano  " = 7 chars
    local sep="          "
    local row1="${user_label}${sep}${plan_label}"
    local row1_len=$(( user_vis_len + ${#sep} + plan_vis_len ))
    draw_panel_row "$row1" "$width" "$row1_len"

    # Linha: Reset
    local reset_label="${C_DIM}Reset${C_RESET}    ${C_CYAN}${reset_fmt}${C_RESET}"
    local reset_vis_len=$(( 9 + ${#reset_fmt} ))
    draw_panel_row "$reset_label" "$width" "$reset_vis_len"

    # Linha: Features
    local feat=""
    local feat_len=12  # "Features  " = 12
    feat="${C_DIM}Features${C_RESET}  "
    if [[ "$chat_enabled" == "true" ]]; then
        feat+="${C_GREEN}✓ Chat${C_RESET}   "
        feat_len=$(( feat_len + 8 ))
    else
        feat+="${C_RED}✗ Chat${C_RESET}   "
        feat_len=$(( feat_len + 8 ))
    fi
    if [[ "$mcp_enabled" == "true" ]]; then
        feat+="${C_GREEN}✓ MCP${C_RESET}   "
        feat_len=$(( feat_len + 7 ))
    else
        feat+="${C_RED}✗ MCP${C_RESET}   "
        feat_len=$(( feat_len + 7 ))
    fi
    if [[ "$copilotignore" == "true" ]]; then
        feat+="${C_GREEN}✓ .copilotignore${C_RESET}"
        feat_len=$(( feat_len + 16 ))
    else
        feat+="${C_DIM}✗ .copilotignore${C_RESET}"
        feat_len=$(( feat_len + 16 ))
    fi
    draw_panel_row "$feat" "$width" "$feat_len"

    draw_panel_bottom "$width"
}

render_quota_panel() {
    local name="$1"
    local snapshot="$2"
    local width="$3"

    local unlimited remaining entitlement pct overage_permitted overage_count
    unlimited=$(echo "$snapshot" | jq -r '.unlimited // false')
    remaining=$(echo "$snapshot" | jq -r '.remaining // 0')
    entitlement=$(echo "$snapshot" | jq -r '.entitlement // 0')
    pct=$(echo "$snapshot" | jq -r '.percent_remaining // 0')
    overage_permitted=$(echo "$snapshot" | jq -r '.overage_permitted // false')
    overage_count=$(echo "$snapshot" | jq -r '.overage_count // 0')

    local display_name
    display_name=$(quota_display_name "$name")
    local inner=$(( width - 4 ))
    local bar_width=$(( inner - 10 ))  # espaço para o rótulo de percentual
    [[ $bar_width -lt 10 ]] && bar_width=10

    draw_panel_top "$display_name" "$width"
    draw_panel_empty_row "$width"

    if [[ "$unlimited" == "true" ]]; then
        # Barra unlimited
        local bar
        bar=$(render_unlimited_bar "$bar_width")
        local bar_label="${C_MAGENTA}${C_BOLD} UNLIMITED${C_RESET}"
        local bar_row="${bar}${bar_label}"
        local bar_vis_len=$(( bar_width + 10 ))
        draw_panel_row "$bar_row" "$width" "$bar_vis_len"

        local info_row="${C_DIM}Sem limite de uso${C_RESET}"
        draw_panel_row "$info_row" "$width" 17

    else
        # Barra com percentual
        local is_overage=false
        local pct_int
        pct_int=$(echo "$pct" | awk '{printf "%d", $1}')
        [[ $pct_int -lt 0 ]] && is_overage=true

        local color
        if [[ "$is_overage" == "true" ]]; then
            color="${C_RED}"
        else
            color=$(bar_color "$pct")
        fi

        local bar_pct=100
        [[ "$is_overage" == "false" ]] && bar_pct="$pct_int"

        local bar
        bar=$(render_gradient_bar "$bar_pct" "$bar_width" "$color")

        # Formatar percentual
        local pct_fmt
        pct_fmt=$(echo "$pct" | awk '{printf "%.1f%%", $1}')

        # Badge de overage
        local badge=""
        local badge_len=0
        if [[ "$is_overage" == "true" ]]; then
            badge=" ${C_RED}${C_BOLD}▲ OVERAGE${C_RESET}"
            badge_len=10
        fi

        local pct_label_len=${#pct_fmt}
        local bar_row="${bar} ${color}${pct_fmt}${C_RESET}${badge}"
        local bar_vis_len=$(( bar_width + 1 + pct_label_len + badge_len ))
        draw_panel_row "$bar_row" "$width" "$bar_vis_len"

        # Segunda linha: números
        local used=$(( entitlement - remaining ))
        [[ $used -lt 0 ]] && used=$(( -1 * remaining ))  # overage: used = entitlement + abs(remaining)
        [[ "$is_overage" == "true" ]] && used=$(( entitlement + (-1 * remaining) ))

        local info=""
        local info_len=0

        if [[ "$is_overage" == "true" ]]; then
            info="${C_DIM}Usado:${C_RESET} ${C_RED}${used}${C_RESET} ${C_DIM}/ ${entitlement}${C_RESET}    ${C_DIM}Overage:${C_RESET} ${C_RED}${remaining}${C_RESET}"
            info_len=$(( 7 + ${#used} + 3 + ${#entitlement} + 11 + ${#remaining} ))
        else
            local remaining_label="${remaining}"
            info="${C_DIM}Restante:${C_RESET} ${C_CYAN}${remaining_label}${C_RESET} ${C_DIM}/ ${entitlement}${C_RESET}"
            info_len=$(( 10 + ${#remaining_label} + 3 + ${#entitlement} ))
        fi

        if [[ "$overage_permitted" == "true" && "$is_overage" == "false" ]]; then
            info+="   ${C_DIM}(overage permitido)${C_RESET}"
            info_len=$(( info_len + 22 ))
        fi

        draw_panel_row "$info" "$width" "$info_len"
    fi

    draw_panel_empty_row "$width"
    draw_panel_bottom "$width"
}

# ─── Tela principal ───────────────────────────────────────────────────────────

render_screen() {
    local json="$1"
    local width
    width=$(panel_width)
    local cols=$(( width + 4 ))

    local buf=""

    # Cabeçalho
    local title=" copilot-api  •  Quota Monitor "
    local title_len=${#title}
    local header_fill=$(( cols - 4 ))
    [[ $header_fill -lt $title_len ]] && header_fill=$title_len
    local pad_total=$(( header_fill - title_len ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))
    local top_border_dashes
    top_border_dashes="$(printf '═%.0s' $(seq 1 $header_fill))"
    local title_spaces_l
    title_spaces_l="$(printf ' %.0s' $(seq 1 $pad_left))"
    local title_spaces_r
    title_spaces_r="$(printf ' %.0s' $(seq 1 $pad_right))"

    buf+="  ${C_HEADER}╔${top_border_dashes}╗${C_RESET}\n"
    buf+="  ${C_HEADER}║${title_spaces_l}${C_BOLD}${C_WHITE}${title}${C_RESET}${C_HEADER}${title_spaces_r}║${C_RESET}\n"
    buf+="  ${C_HEADER}╚${top_border_dashes}╝${C_RESET}\n"
    buf+="\n"

    # Painel de informações da conta
    buf+="  $(render_info_panel "$json" "$width")\n"
    buf+="\n"

    # Painéis de quota
    local quota_keys=("chat" "completions" "premium_interactions")
    for key in "${quota_keys[@]}"; do
        local snapshot
        snapshot=$(echo "$json" | jq -c ".quota_snapshots.${key} // null")
        if [[ "$snapshot" != "null" && -n "$snapshot" ]]; then
            buf+="  $(render_quota_panel "$key" "$snapshot" "$width")\n"
            buf+="\n"
        fi
    done

    # Rodapé
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    local footer="  ${C_DIM}Atualizado: ${C_RESET}${C_CYAN}${timestamp}${C_RESET}  ${C_BORDER}│${C_RESET}  ${C_DIM}Intervalo: ${C_RESET}${C_CYAN}${INTERVAL}s${C_RESET}  ${C_BORDER}│${C_RESET}  ${C_DIM}Ctrl+C para sair${C_RESET}"
    buf+="${footer}\n"

    # Imprime atomicamente (sem flicker)
    printf '\033[H\033[2J'
    printf '%b' "$buf"
}

draw_offline_screen() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    printf '\033[H\033[2J'
    printf '\n'
    printf '  %s╔══════════════════════════════════════════════╗%s\n' "${C_BORDER}" "${C_RESET}"
    printf '  %s║%s  %scopilot-api  •  Quota Monitor%s              %s║%s\n' "${C_BORDER}" "${C_RESET}" "${C_BOLD}${C_WHITE}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s╚══════════════════════════════════════════════╝%s\n' "${C_BORDER}" "${C_RESET}"
    printf '\n'
    printf '  %s┌─ Status ─────────────────────────────────────┐%s\n' "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s                                               %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s  %s⚠  Aguardando copilot-api em %s%s...%s         %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_YELLOW}${C_BOLD}" "${C_CYAN}" "${API_URL}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s                                               %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s  %sÚltima tentativa:%s %s%-12s%s              %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_DIM}" "${C_RESET}" "${C_CYAN}" "${timestamp}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s  %sPróxima em %s%ss...%s                         %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_DIM}" "${C_RESET}" "${INTERVAL}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s│%s                                               %s│%s\n' "${C_BORDER}" "${C_RESET}" "${C_BORDER}" "${C_RESET}"
    printf '  %s└───────────────────────────────────────────────┘%s\n' "${C_BORDER}" "${C_RESET}"
    printf '\n'
    printf '  %sCtrl+C para sair%s\n' "${C_DIM}" "${C_RESET}"
}

# ─── Cleanup e loop principal ─────────────────────────────────────────────────

cleanup() {
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    printf '\n'
    printf 'Dashboard encerrado.\n'
    exit 0
}

main() {
    check_deps

    tput smcup 2>/dev/null || true
    tput civis 2>/dev/null || true
    trap cleanup INT TERM

    while true; do
        local json=""
        json="$(fetch_usage 2>/dev/null)" || json=""

        if [[ -z "$json" ]]; then
            draw_offline_screen
        else
            render_screen "$json"
        fi

        sleep "${INTERVAL}"
    done
}

main
