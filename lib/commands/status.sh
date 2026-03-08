#!/usr/bin/env bash
# Command: df status
# Description: Show status, ports, CPU/MEM and volumes for all managed containers

# Column widths
readonly _ST_W_NAME=30
readonly _ST_W_STATUS=42
readonly _ST_W_PORT=18
readonly _ST_W_CPU=5
readonly _ST_W_MEM=9
readonly _ST_SEP="$(printf '─%.0s' $(seq 1 110))"

# Builds a lookup map (associative array) from docker stats --no-stream.
# Populates global _STATS_MAP["name"]="cpu\tmem\tmem_pct"
declare -gA _STATS_MAP=()
_status_load_stats() {
  _STATS_MAP=()
  local line
  while IFS=$'\t' read -r sname scpu smem smem_pct; do
    [[ -z "${sname}" ]] && continue
    _STATS_MAP["${sname}"]="${scpu}"$'\t'"${smem}"$'\t'"${smem_pct}"
  done < <(docker stats --no-stream \
    --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null || true)
}

# Prints a section header with column titles.
# Args: $1 - section label (e.g. "Platform")
_status_section_header() {
  local label="${1}"
  echo ""
  echo "  ${COLOR_CYAN}${label}${COLOR_RESET}"
  printf "  ${COLOR_GRAY}%-${_ST_W_NAME}s  %-${_ST_W_STATUS}s  %-${_ST_W_PORT}s  %${_ST_W_CPU}s  %${_ST_W_MEM}s${COLOR_RESET}\n" \
    "NAME" "STATUS" "PORTS" "CPU%" "MEM"
  echo "  ${COLOR_GRAY}${_ST_SEP}${COLOR_RESET}"
}

# Prints a single container row.
# Args: $1=name $2=status $3=ports
_status_print_row() {
  local name="${1}" status="${2}" ports="${3}"
  local cpu="—" mem="—"

  if [[ -n "${_STATS_MAP[${name}]+_}" ]]; then
    IFS=$'\t' read -r cpu mem _ <<< "${_STATS_MAP[${name}]}"
    mem="${mem%% /*}"  # Show only used portion (e.g. "87.22MiB" not "87.22MiB / 31.09GiB")
  fi

  local ports_display="${ports:0:${_ST_W_PORT}}"
  local color
  color="$(docker_status_color "${status}")"

  printf "  %-${_ST_W_NAME}s  ${color}%-${_ST_W_STATUS}s${COLOR_RESET}  %-${_ST_W_PORT}s  %${_ST_W_CPU}s  %${_ST_W_MEM}s\n" \
    "${name}" "${status:0:${_ST_W_STATUS}}" "${ports_display}" "${cpu}" "${mem}"
}

# Prints containers for a given df.type label (platform, infra, project).
# Args: $1 - section label, $2 - df.type value
_status_show_section() {
  local label="${1}" df_type="${2}"
  _status_section_header "${label}"

  local found=false
  while IFS=$'\t' read -r name status ports; do
    [[ -z "${name}" ]] && continue
    found=true
    _status_print_row "${name}" "${status}" "${ports}"
  done < <(docker ps -a \
    --filter "label=managed-by=docker-framework" \
    --filter "label=df.type=${df_type}" \
    --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)

  if [[ "${found}" == false ]]; then
    echo "  ${COLOR_GRAY}(no ${label,,} containers)${COLOR_RESET}"
  fi
}

# Prints the volumes section for all managed containers.
_status_show_volumes() {
  echo ""
  echo "  ${COLOR_CYAN}Volumes${COLOR_RESET}"
  printf "  ${COLOR_GRAY}%-50s  %-28s  %s${COLOR_RESET}\n" "VOLUME" "CONTAINER" "SIZE"
  echo "  ${COLOR_GRAY}${_ST_SEP}${COLOR_RESET}"

  local count=0
  while IFS= read -r container_name; do
    [[ -z "${container_name}" ]] && continue
    local mounts
    mounts="$(docker inspect --format \
      '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
      "${container_name}" 2>/dev/null | grep -v '^$' || true)"

    while IFS= read -r vol_name; do
      [[ -z "${vol_name}" ]] && continue
      count=$(( count + 1 ))
      local vol_path size="?"
      vol_path="$(docker volume inspect --format '{{.Mountpoint}}' "${vol_name}" 2>/dev/null || true)"
      [[ -n "${vol_path}" ]] && [[ -d "${vol_path}" ]] && \
        size="$(du -sh "${vol_path}" 2>/dev/null | cut -f1 || echo "?")"
      printf "  %-50s  %-28s  %s\n" \
        "${vol_name:0:50}" "${container_name:0:28}" "${size}"
    done <<< "${mounts}"
  done < <(docker ps -a \
    --filter "label=managed-by=docker-framework" \
    --format "{{.Names}}" 2>/dev/null || true)

  if [[ "${count}" -eq 0 ]]; then
    echo "  ${COLOR_GRAY}(no volumes)${COLOR_RESET}"
  fi
  echo ""
}

# Full status render (called once or in refresh loop).
_status_render() {
  log_header "df status"
  _status_load_stats
  _status_show_section "Platform"       "platform"
  _status_show_section "Infrastructure" "infra"
  _status_show_section "Projects"       "project"
  _status_show_volumes
}

# Shows the status of all containers managed by docker-framework.
# Can be run from any directory.
cmd_status() {
  local refresh_mode=false
  local refresh_interval=10

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --refresh)
        refresh_mode=true
        if [[ -n "${2:-}" ]] && [[ "${2}" =~ ^[0-9]+$ ]]; then
          refresh_interval="${2}"; shift
        fi
        shift
        ;;
      -h|--help)  _status_usage; return 0 ;;
      *)          log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  if [[ "${refresh_mode}" == true ]]; then
    # First render: clear screen once upfront
    clear
    while true; do
      # Render everything into a buffer FIRST (docker stats takes time)
      # Only then swap — screen is never blank during data collection
      local output
      output="$(_status_render; log_detail "Auto-refresh every ${refresh_interval}s — last updated $(date '+%H:%M:%S') — Ctrl+C to stop")"
      # Atomic: cursor home + clear screen + print buffer in one write
      printf '\033[H\033[2J%s\n' "${output}"
      sleep "${refresh_interval}"
    done
  else
    _status_render
  fi
}

# Shows usage for the status command.
_status_usage() {
  cat <<EOF
Usage: df status [options]

Show status, ports, CPU% and memory for all managed containers,
grouped by type (Platform / Infrastructure / Projects).
Also lists Docker volumes and their sizes.

Options:
  --refresh [N]   Auto-refresh every N seconds (default: 10)
  -h, --help      Show this help message

This command can be run from any directory.

Examples:
  df status              # Show once
  df status --refresh    # Auto-refresh every 10s
  df status --refresh 5  # Auto-refresh every 5s
EOF
}
