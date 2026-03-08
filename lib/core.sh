#!/usr/bin/env bash
# Core utilities: logging, validation, and common helpers.
# This file MUST NOT contain business logic.

# --- Colors ---
readonly COLOR_RED=$'\033[0;31m'
readonly COLOR_GREEN=$'\033[0;32m'
readonly COLOR_YELLOW=$'\033[0;33m'
readonly COLOR_BLUE=$'\033[0;34m'
readonly COLOR_CYAN=$'\033[0;36m'
readonly COLOR_GRAY=$'\033[0;90m'
readonly COLOR_RESET=$'\033[0m'

# --- Logging ---

# Logs an informational message to stdout.
# Args: $1 - message
log_info() {
  echo -e "${COLOR_BLUE}ℹ ${COLOR_RESET} ${1}"
}

# Logs a success message to stdout.
# Args: $1 - message
log_success() {
  echo -e "${COLOR_GREEN}✓ ${COLOR_RESET} ${1}"
}

# Logs a warning message to stdout.
# Args: $1 - message
log_warn() {
  echo -e "${COLOR_YELLOW}⚠ ${COLOR_RESET} ${1}" >&2
}

# Logs an error message to stderr.
# Args: $1 - message
log_error() {
  echo -e "${COLOR_RED}✗ ${COLOR_RESET} ${1}" >&2
}

# Logs an action step in progress (cyan).
# Args: $1 - message
log_step() {
  echo -e "${COLOR_CYAN}☑ ${COLOR_RESET} ${1}"
}

# Logs a sub-item / detail (gray).
# Args: $1 - message
log_detail() {
  echo -e "${COLOR_GRAY}  🏷  ${1}${COLOR_RESET}"
}

# Prints a visual separator line.
log_separator() {
  echo -e "${COLOR_GRAY}────────────────────────────────────────────${COLOR_RESET}"
}

# Prints a framed section header (41-char box).
# Args: $1 - title
log_header() {
  local title="${1}"
  local width=41
  local padding=$(( width - ${#title} - 2 ))
  local pad
  pad="$(printf ' %.0s' $(seq 1 "${padding}"))"
  echo -e "${COLOR_CYAN}╭─────────────────────────────────────────╮${COLOR_RESET}"
  echo -e "${COLOR_CYAN}│${COLOR_RESET} ${title} ${COLOR_GRAY}${pad}${COLOR_CYAN}│${COLOR_RESET}"
  echo -e "${COLOR_CYAN}╰─────────────────────────────────────────╯${COLOR_RESET}"
}

# Maps a Docker container status string to an ANSI color code.
# Args: $1 - status string (e.g. "Up 5 days (healthy)")
# Returns: color escape code via stdout
docker_status_color() {
  local status="${1}"
  if [[ "${status}" =~ healthy ]]; then
    echo "${COLOR_GREEN}"
  elif [[ "${status}" =~ unhealthy|starting|restarting ]] || [[ "${status}" =~ Up\ [0-9]+\ second ]]; then
    echo "${COLOR_YELLOW}"
  elif [[ "${status}" =~ Exited|Dead|Created ]]; then
    echo "${COLOR_RED}"
  else
    echo "${COLOR_RESET}"
  fi
}

# Formats memory from MiB to human-readable MiB or GiB.
# Args: $1 - value in MiB (numeric)
# Returns: formatted string (e.g. "512.00MiB" or "1.50GiB")
docker_format_memory() {
  local mem_mib="${1}"
  if command -v bc &>/dev/null && (( $(echo "${mem_mib} >= 1024" | bc -l) )); then
    echo "$(echo "scale=2; ${mem_mib}/1024" | bc)GiB"
  else
    printf "%.2fMiB" "${mem_mib}"
  fi
}

# --- Validation ---

# Validates that required tools are installed.
# Returns: 0 if all tools present, 1 otherwise
validate_prerequisites() {
  local missing=0

  if ! command -v docker &>/dev/null; then
    log_error "docker is not installed or not in PATH"
    missing=1
  fi

  if ! command -v docker compose &>/dev/null 2>&1; then
    # Try docker-compose as fallback
    if ! command -v docker-compose &>/dev/null; then
      log_error "docker compose is not installed or not in PATH"
      missing=1
    fi
  fi

  if ! command -v yq &>/dev/null; then
    log_error "yq is not installed or not in PATH (required for YAML parsing)"
    missing=1
  fi

  return "${missing}"
}

# Validates that the project directory (DF_PROJECT_DIR or cwd) has a df.yml.
# Returns: 0 if valid, 1 otherwise
validate_project_context() {
  local dir="${DF_PROJECT_DIR:-${PWD}}"
  if [[ ! -f "${dir}/df.yml" ]]; then
    log_error "No df.yml found in ${dir}"
    log_error "Run from a project directory or pass a slug: df <cmd> project-pm-obsidian"
    return 1
  fi
  return 0
}

# Finds the df.yml in the project directory (DF_PROJECT_DIR or cwd).
# Returns: absolute path to df.yml (stdout)
find_df_yml() {
  local dir="${DF_PROJECT_DIR:-${PWD}}"
  local df_yml="${dir}/df.yml"
  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found in ${dir}"
    return 1
  fi
  echo "${df_yml}"
}

# Resolves a project slug to its directory path.
# Slug is the relative path from ROOT_DIR with '/' replaced by '-'.
# Example: "project-pm-obsidian" -> "${ROOT_DIR}/project-pm/obsidian"
# Args: $1 - project slug
# Returns: absolute path to project directory (stdout)
resolve_project_dir_by_slug() {
  local slug="${1}"
  local found=""

  while IFS= read -r df_yml_path; do
    local dir relative slug_candidate
    dir="$(dirname "${df_yml_path}")"
    relative="${dir#${ROOT_DIR}/}"
    slug_candidate="${relative//\//-}"
    if [[ "${slug_candidate}" == "${slug}" ]]; then
      found="${dir}"
      break
    fi
  done < <(find "${ROOT_DIR}" -name "df.yml" \
    -not -path "*/templates/*" \
    -not -path "*/platform/*" 2>/dev/null)

  if [[ -z "${found}" ]]; then
    local available
    available="$(find "${ROOT_DIR}" -name "df.yml" \
      -not -path "*/templates/*" -not -path "*/platform/*" \
      | sed "s|${ROOT_DIR}/||;s|/df.yml||;s|/|-|g" | sort | tr '\n' ' ')"
    log_error "Project not found: ${slug}"
    log_error "Available: ${available}"
    return 1
  fi

  echo "${found}"
}

# --- Docker Helpers ---

# Ensures the shared df-network exists.
ensure_network() {
  if ! docker network inspect df-network &>/dev/null; then
    log_info "Creating df-network..."
    docker network create df-network >/dev/null
    log_success "df-network created"
  fi
}

# Checks if a container is running.
# Args: $1 - container name
# Returns: 0 if running, 1 otherwise
is_container_running() {
  local container_name="${1}"
  docker ps --filter "name=^${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Checks if a container exists (running or stopped).
# Args: $1 - container name
# Returns: 0 if exists, 1 otherwise
container_exists() {
  local container_name="${1}"
  docker ps -a --filter "name=^${container_name}$" --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Waits for a container to be healthy.
# Args: $1 - container name, $2 - timeout in seconds (default 60)
# Returns: 0 if healthy, 1 if timeout
wait_for_healthy() {
  local container_name="${1}"
  local timeout="${2:-60}"
  local elapsed=0

  log_info "Waiting for ${container_name} to be healthy..."

  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    local health
    health="$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "none")"

    if [[ "${health}" == "healthy" ]]; then
      log_success "${container_name} is healthy"
      return 0
    fi

    if [[ "${health}" == "none" ]]; then
      # No healthcheck defined, just check if running
      if is_container_running "${container_name}"; then
        log_success "${container_name} is running (no healthcheck)"
        return 0
      fi
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  log_error "${container_name} did not become healthy within ${timeout}s"
  return 1
}

# Lists all containers managed by docker-framework.
# Returns: container info (stdout)
list_managed_containers() {
  docker ps -a \
    --filter "label=managed-by=docker-framework" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
