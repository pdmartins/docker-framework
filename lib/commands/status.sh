#!/usr/bin/env bash
# Command: df status
# Description: Show status of all managed containers

# shellcheck source=../core.sh
source "${LIB_DIR}/core.sh"

# Shows the status of all containers managed by docker-framework.
# Can be run from any directory.
# Args: $@ - options
cmd_status() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -h|--help)  _status_usage; return 0 ;;
      *)          log_error "Unknown option: ${1}"; return 1 ;;
    esac
  done

  log_info "Docker Framework — Container Status"
  echo ""

  # Infrastructure containers
  echo "Infrastructure:"
  printf "  %-25s %-15s %s\n" "NAME" "STATUS" "PORTS"
  printf "  %-25s %-15s %s\n" "----" "------" "-----"

  local infra_found=false
  while IFS=$'\t' read -r name status ports; do
    [[ -z "${name}" ]] && continue
    infra_found=true
    printf "  %-25s %-15s %s\n" "${name}" "${status}" "${ports}"
  done < <(docker ps -a \
    --filter "label=managed-by=docker-framework" \
    --filter "label=df.type=infra" \
    --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)

  if [[ "${infra_found}" == false ]]; then
    echo "  (no infrastructure containers)"
  fi

  echo ""

  # Project containers
  echo "Projects:"
  printf "  %-25s %-15s %s\n" "NAME" "STATUS" "PORTS"
  printf "  %-25s %-15s %s\n" "----" "------" "-----"

  local projects_found=false
  while IFS=$'\t' read -r name status ports; do
    [[ -z "${name}" ]] && continue
    projects_found=true
    printf "  %-25s %-15s %s\n" "${name}" "${status}" "${ports}"
  done < <(docker ps -a \
    --filter "label=managed-by=docker-framework" \
    --filter "label=df.type=project" \
    --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)

  if [[ "${projects_found}" == false ]]; then
    echo "  (no project containers)"
  fi

  echo ""
}

# Shows usage for the status command.
_status_usage() {
  cat <<EOF
Usage: df status

Show status of all containers managed by docker-framework.

This command can be run from any directory.
EOF
}
