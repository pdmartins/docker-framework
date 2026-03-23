#!/usr/bin/env bash
# Init script execution: runs project-specific initialization scripts
# inside infrastructure containers.

# --- Default service credentials ---
# These defaults match the values set in each service's docker-compose template.
# Override per project by setting these variables in the project's .env file.
: "${INIT_POSTGRESQL_USER:=postgres}"
: "${INIT_POSTGRESQL_DB:=postgres}"
: "${INIT_MONGODB_USER:=root}"
: "${INIT_MONGODB_PASSWORD:=root}"
: "${INIT_SQL_SERVER_USER:=sa}"
: "${INIT_SQL_SERVER_PASSWORD:=YourStrong!Passw0rd}"

# Executes all init scripts for a project's dependencies.
# Args: $1 - path to df.yml
# Returns: 0 if all succeeded, 1 if any failed
run_all_init_scripts() {
  local df_yml="${1}"
  local app_dir
  app_dir="$(dirname "${df_yml}")"
  local init_dir="${app_dir}/init"
  local failed=0

  if [[ ! -d "${init_dir}" ]]; then
    log_info "No init directory found, skipping init scripts"
    return 0
  fi

  # Resolve project metadata for container names
  resolve_project_metadata "${df_yml}"

  # Load project .env into shell so credential overrides are available to init handlers
  if [[ -f "${PROJECT_DIR}/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${PROJECT_DIR}/.env"
    set +a
  fi

  local deps
  deps="$(resolve_infra_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    # Find init script for this dependency
    local init_file
    init_file="$(find_init_script "${init_dir}" "${dep}")"

    if [[ -z "${init_file}" ]]; then
      continue
    fi

    if [[ "${DF_DRY_RUN:-false}" == "true" ]]; then
      log_step "[DRY-RUN] Would run init script for ${dep}: ${init_file}"
      continue
    fi

    log_info "Running init script for ${dep}..."

    if ! run_init_script "${dep}" "${init_file}" "${PROJECT_SLUG}"; then
      log_error "Init script failed for ${dep}"
      failed=1
    else
      log_success "Init script completed for ${dep}"
    fi
  done <<< "${deps}"

  return "${failed}"
}

# Finds the init script file for a given resource.
# Args: $1 - init directory, $2 - resource name
# Returns: path to init script (stdout), empty if not found
find_init_script() {
  local init_dir="${1}"
  local resource="${2}"

  # Check common extensions
  for ext in sql sh js py; do
    local file="${init_dir}/${resource}.${ext}"
    if [[ -f "${file}" ]]; then
      echo "${file}"
      return 0
    fi
  done

  return 0
}

# Dispatches init script execution to the appropriate handler.
# Args: $1 - resource name, $2 - init script path, $3 - project slug
# Returns: 0 on success, 1 on failure
run_init_script() {
  local resource="${1}"
  local init_file="${2}"
  local project_slug="${3}"
  local ext="${init_file##*.}"
  local container_name="infra-${project_slug}-${resource}"

  case "${resource}" in
    sql_server)   run_init_sql_server "${init_file}" "${container_name}" ;;
    postgresql)   run_init_postgresql "${init_file}" "${container_name}" ;;
    kafka)        run_init_kafka "${init_file}" "${container_name}" ;;
    mongodb)      run_init_mongodb "${init_file}" "${container_name}" ;;
    rabbitmq)     run_init_rabbitmq "${init_file}" "${container_name}" ;;
    redis)        run_init_redis "${init_file}" "${container_name}" ;;
    *)
      # Generic handler based on extension
      case "${ext}" in
        sql)  run_init_generic_sql "${container_name}" "${init_file}" ;;
        sh)   run_init_generic_sh "${container_name}" "${init_file}" ;;
        js)   run_init_generic_js "${container_name}" "${init_file}" ;;
        *)    log_warn "No init handler for ${resource} (${ext})" ;;
      esac
      ;;
  esac
}

# --- Resource-specific init executors ---

# Executes SQL Server init script via sqlcmd.
# Args: $1 - init script path, $2 - container name
run_init_sql_server() {
  local init_file="${1}"
  local container_name="${2}"

  docker exec -i "${container_name}" /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U "${INIT_SQL_SERVER_USER}" -P "${INIT_SQL_SERVER_PASSWORD}" \
    -C -i "/dev/stdin" < "${init_file}"
}

# Executes PostgreSQL init script via psql.
# Args: $1 - init script path, $2 - container name
run_init_postgresql() {
  local init_file="${1}"
  local container_name="${2}"

  docker exec -i "${container_name}" psql \
    -U "${INIT_POSTGRESQL_USER}" -d "${INIT_POSTGRESQL_DB}" \
    < "${init_file}"
}

# Executes Kafka init script via bash in container.
# Args: $1 - init script path, $2 - container name
run_init_kafka() {
  local init_file="${1}"
  local container_name="${2}"
  docker exec -i "${container_name}" bash < "${init_file}"
}

# Executes MongoDB init script via mongosh.
# Args: $1 - init script path, $2 - container name
run_init_mongodb() {
  local init_file="${1}"
  local container_name="${2}"

  docker exec -i "${container_name}" mongosh \
    -u "${INIT_MONGODB_USER}" -p "${INIT_MONGODB_PASSWORD}" \
    --authenticationDatabase admin \
    < "${init_file}"
}

# Executes RabbitMQ init script via bash in container.
# Args: $1 - init script path, $2 - container name
run_init_rabbitmq() {
  local init_file="${1}"
  local container_name="${2}"
  docker exec -i "${container_name}" bash < "${init_file}"
}

# Redis typically doesn't need init scripts.
# Args: $1 - init script path, $2 - container name
run_init_redis() {
  local init_file="${1}"
  local container_name="${2}"
  log_info "Redis init scripts are typically not needed (databases 0-15 exist by default)"
  if [[ -f "${init_file}" ]]; then
    docker exec -i "${container_name}" redis-cli < "${init_file}"
  fi
}

# --- Generic init executors ---

# Executes a generic SQL init script.
# Args: $1 - container name, $2 - init file path
run_init_generic_sql() {
  local container_name="${1}"
  local init_file="${2}"
  log_warn "Using generic SQL executor for ${container_name} — consider adding a specific handler"
  docker exec -i "${container_name}" sh -c 'cat > /tmp/init.sql && echo "Init script copied"' < "${init_file}"
}

# Executes a generic shell init script.
# Args: $1 - container name, $2 - init file path
run_init_generic_sh() {
  local container_name="${1}"
  local init_file="${2}"
  docker exec -i "${container_name}" bash < "${init_file}"
}

# Executes a generic JavaScript init script.
# Args: $1 - container name, $2 - init file path
run_init_generic_js() {
  local container_name="${1}"
  local init_file="${2}"
  docker exec -i "${container_name}" node < "${init_file}"
}
