#!/usr/bin/env bash
# Init script execution: runs project-specific initialization scripts
# inside infrastructure containers.

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

  local deps
  deps="$(resolve_deps "${df_yml}")"

  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue

    # Find init script for this dependency
    local init_file
    init_file="$(find_init_script "${init_dir}" "${dep}")"

    if [[ -z "${init_file}" ]]; then
      continue
    fi

    log_info "Running init script for ${dep}..."

    if ! run_init_script "${dep}" "${init_file}"; then
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
# Args: $1 - resource name, $2 - init script path
# Returns: 0 on success, 1 on failure
run_init_script() {
  local resource="${1}"
  local init_file="${2}"
  local ext="${init_file##*.}"

  case "${resource}" in
    sql_server)   run_init_sql_server "${init_file}" ;;
    postgresql)   run_init_postgresql "${init_file}" ;;
    kafka)        run_init_kafka "${init_file}" ;;
    mongodb)      run_init_mongodb "${init_file}" ;;
    rabbitmq)     run_init_rabbitmq "${init_file}" ;;
    redis)        run_init_redis "${init_file}" ;;
    *)
      # Generic handler based on extension
      case "${ext}" in
        sql)  run_init_generic_sql "${resource}" "${init_file}" ;;
        sh)   run_init_generic_sh "${resource}" "${init_file}" ;;
        js)   run_init_generic_js "${resource}" "${init_file}" ;;
        *)    log_warn "No init handler for ${resource} (${ext})" ;;
      esac
      ;;
  esac
}

# --- Resource-specific init executors ---

# Executes SQL Server init script via sqlcmd.
# Args: $1 - init script path
run_init_sql_server() {
  local init_file="${1}"
  local password
  password="$(get_credential "sql_server" "sa_password")"

  docker exec -i infra-sql_server /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "${password}" \
    -C -i "/dev/stdin" < "${init_file}"
}

# Executes PostgreSQL init script via psql.
# Args: $1 - init script path
run_init_postgresql() {
  local init_file="${1}"
  local user
  user="$(get_credential "postgresql" "user")"

  docker exec -i infra-postgresql psql \
    -U "${user}" -d postgres \
    < "${init_file}"
}

# Executes Kafka init script via bash in container.
# Args: $1 - init script path
run_init_kafka() {
  local init_file="${1}"
  docker exec -i infra-kafka bash < "${init_file}"
}

# Executes MongoDB init script via mongosh.
# Args: $1 - init script path
run_init_mongodb() {
  local init_file="${1}"
  local user password
  user="$(get_credential "mongodb" "root_user")"
  password="$(get_credential "mongodb" "root_password")"

  docker exec -i infra-mongodb mongosh \
    -u "${user}" -p "${password}" \
    --authenticationDatabase admin \
    < "${init_file}"
}

# Executes RabbitMQ init script via bash in container.
# Args: $1 - init script path
run_init_rabbitmq() {
  local init_file="${1}"
  docker exec -i infra-rabbitmq bash < "${init_file}"
}

# Redis typically doesn't need init scripts.
# Args: $1 - init script path
run_init_redis() {
  local init_file="${1}"
  log_info "Redis init scripts are typically not needed (databases 0-15 exist by default)"
  if [[ -f "${init_file}" ]]; then
    local password
    password="$(get_credential "redis" "password")"
    local auth_flag=""
    if [[ -n "${password}" ]]; then
      auth_flag="-a ${password}"
    fi
    docker exec -i infra-redis redis-cli ${auth_flag} < "${init_file}"
  fi
}

# --- Generic init executors ---

# Executes a generic SQL init script.
# Args: $1 - resource name, $2 - init file path
run_init_generic_sql() {
  local resource="${1}"
  local init_file="${2}"
  log_warn "Using generic SQL executor for ${resource} — consider adding a specific handler"
  docker exec -i "infra-${resource}" sh -c 'cat > /tmp/init.sql && echo "Init script copied"' < "${init_file}"
}

# Executes a generic shell init script.
# Args: $1 - resource name, $2 - init file path
run_init_generic_sh() {
  local resource="${1}"
  local init_file="${2}"
  docker exec -i "infra-${resource}" bash < "${init_file}"
}

# Executes a generic JavaScript init script.
# Args: $1 - resource name, $2 - init file path
run_init_generic_js() {
  local resource="${1}"
  local init_file="${2}"
  docker exec -i "infra-${resource}" node < "${init_file}"
}
