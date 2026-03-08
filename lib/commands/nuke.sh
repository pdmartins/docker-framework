#!/usr/bin/env bash
# Command: df nuke
# Description: Clean up Docker resources (soft: stop + prune images, hard: full reset)

# Performs a soft nuke: stops managed containers and prunes unused images.
# No confirmation required.
_nuke_soft() {
  log_header "df nuke soft"
  echo ""

  # Stop all managed containers
  log_step "Stopping managed containers..."
  local stopped=0
  while IFS= read -r name; do
    [[ -z "${name}" ]] && continue
    log_detail "Stopping ${name}..."
    docker stop "${name}" &>/dev/null || true
    stopped=$(( stopped + 1 ))
  done < <(docker ps \
    --filter "label=managed-by=docker-framework" \
    --format "{{.Names}}" 2>/dev/null || true)

  if [[ "${stopped}" -gt 0 ]]; then
    log_success "${stopped} container(s) stopped"
  else
    log_info "No running managed containers found"
  fi

  echo ""

  # Prune unused images
  log_step "Pruning unused Docker images..."
  docker image prune -a -f 2>&1 | grep -E "^(Total|deleted)" | while IFS= read -r line; do
    log_detail "${line}"
  done
  log_success "Image prune complete"
  echo ""
}

# Performs a hard nuke: stops ALL containers, removes them, removes ALL images, system prune.
# Requires confirmation.
_nuke_hard() {
  log_header "df nuke hard"
  echo ""
  log_warn "⚠  This will:"
  log_warn "   • Stop and REMOVE ALL Docker containers on this host"
  log_warn "   • Remove ALL Docker images"
  log_warn "   • Run docker system prune -af"
  log_warn "   This is IRREVERSIBLE."
  echo ""
  read -rp "  Type 'yes' to confirm: " confirm
  if [[ "${confirm}" != "yes" ]]; then
    log_info "Aborted"
    return 0
  fi

  echo ""

  # Stop all containers
  log_step "Stopping all containers..."
  local all_containers
  all_containers="$(docker ps -q 2>/dev/null || true)"
  if [[ -n "${all_containers}" ]]; then
    # shellcheck disable=SC2086
    docker stop ${all_containers} &>/dev/null || true
    log_success "All containers stopped"
  else
    log_info "No running containers"
  fi

  # Remove all containers
  log_step "Removing all containers..."
  local all_stopped
  all_stopped="$(docker ps -aq 2>/dev/null || true)"
  if [[ -n "${all_stopped}" ]]; then
    # shellcheck disable=SC2086
    docker rm -f ${all_stopped} &>/dev/null || true
    log_success "All containers removed"
  else
    log_info "No containers to remove"
  fi

  # Remove all images
  log_step "Removing all images..."
  local all_images
  all_images="$(docker images -q 2>/dev/null || true)"
  if [[ -n "${all_images}" ]]; then
    # shellcheck disable=SC2086
    docker rmi -f ${all_images} &>/dev/null || true
    log_success "All images removed"
  else
    log_info "No images to remove"
  fi

  # System prune
  log_step "Running docker system prune..."
  docker system prune -af 2>&1 | tail -n2 | while IFS= read -r line; do
    log_detail "${line}"
  done
  log_success "System prune complete"

  echo ""
  log_separator
  log_success "Hard nuke complete — Docker is now clean"
}

# Main nuke command dispatcher.
cmd_nuke() {
  case "${1:-}" in
    soft)       _nuke_soft ;;
    hard)       _nuke_hard ;;
    -h|--help)  _nuke_usage; return 0 ;;
    "")
      log_error "Specify: df nuke soft|hard"
      _nuke_usage
      return 1
      ;;
    *)
      log_error "Unknown nuke mode: ${1}"
      _nuke_usage
      return 1
      ;;
  esac
}

# Shows usage for the nuke command.
_nuke_usage() {
  cat <<EOF
Usage: df nuke <mode>

Clean up Docker resources.

Modes:
  soft   Stop managed containers and prune unused images (no confirmation)
  hard   Stop+remove ALL containers, ALL images, and run system prune (requires "yes")

Options:
  -h, --help   Show this help message

Examples:
  df nuke soft   # Gentle cleanup
  df nuke hard   # Full reset (DESTRUCTIVE)
EOF
}
