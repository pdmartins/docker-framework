#!/usr/bin/env bash
# Core utilities: logging, validation, and common helpers.
# This file MUST NOT contain business logic.

# --- Colors ---
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# --- Logging ---

# Logs an informational message to stdout.
# Args: $1 - message
log_info() {
  echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} ${1}"
}

# Logs a success message to stdout.
# Args: $1 - message
log_success() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} ${1}"
}

# Logs a warning message to stdout.
# Args: $1 - message
log_warn() {
  echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} ${1}" >&2
}

# Logs an error message to stderr.
# Args: $1 - message
log_error() {
  echo -e "${COLOR_RED}✗${COLOR_RESET} ${1}" >&2
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

# Validates that the current directory is inside a project app directory (has df.yml).
# Returns: 0 if valid, 1 otherwise
validate_project_context() {
  if [[ ! -f "df.yml" ]]; then
    log_error "No df.yml found in current directory"
    log_error "Run this command from a project app directory (e.g., project-team/app/)"
    return 1
  fi
  return 0
}

# Finds the df.yml in the current directory.
# Returns: absolute path to df.yml (stdout)
find_df_yml() {
  local df_yml="${PWD}/df.yml"
  if [[ ! -f "${df_yml}" ]]; then
    log_error "df.yml not found in ${PWD}"
    return 1
  fi
  echo "${df_yml}"
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
