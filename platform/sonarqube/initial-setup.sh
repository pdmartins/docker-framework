#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: initial-setup.sh
# Description: Prepares the host environment for running SonarQube platform
#              service. Idempotent — safe to run multiple times.
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Helpers
print_info()    { echo -e "${CYAN}🔍 $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_step()    { echo -e "${WHITE}🚀 $1${NC}"; }

# Script directory (platform/sonarqube/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Required vm.max_map_count for Elasticsearch (used by SonarQube)
REQUIRED_MAP_COUNT=524288

# Error handling
trap 'print_error "Error on line $LINENO"; exit 1' ERR

# ============================================================================
# Functions
# ============================================================================

configure_vm_max_map_count() {
    local current
    current="$(sysctl -n vm.max_map_count)"
    print_info "Current vm.max_map_count: ${current}"

    if [[ "${current}" -ge "${REQUIRED_MAP_COUNT}" ]]; then
        print_success "vm.max_map_count already satisfies the requirement (>= ${REQUIRED_MAP_COUNT})"
        return 0
    fi

    print_step "Setting vm.max_map_count to ${REQUIRED_MAP_COUNT}..."
    sudo sysctl -w vm.max_map_count="${REQUIRED_MAP_COUNT}"

    local sysctl_conf="/etc/sysctl.conf"
    if grep -q '^vm.max_map_count=' "${sysctl_conf}" 2>/dev/null; then
        print_warning "vm.max_map_count already defined in ${sysctl_conf} — updating value"
        sudo sed -i "s/^vm.max_map_count=.*/vm.max_map_count=${REQUIRED_MAP_COUNT}/" "${sysctl_conf}"
    else
        echo "vm.max_map_count=${REQUIRED_MAP_COUNT}" | sudo tee -a "${sysctl_conf}" > /dev/null
    fi

    sudo sysctl -p
    print_success "vm.max_map_count set to ${REQUIRED_MAP_COUNT} (persistent)"
}

create_volumes() {
    local volumes_dir="${SCRIPT_DIR}/volumes"
    local dirs=("data" "logs" "extensions")

    print_info "Ensuring volume directories exist under ${volumes_dir}..."

    for dir in "${dirs[@]}"; do
        local target="${volumes_dir}/${dir}"
        if [[ -d "${target}" ]]; then
            print_warning "Already exists: ${target}"
        else
            mkdir -p "${target}"
            print_success "Created: ${target}"
        fi
    done
}

main() {
    print_step "SonarQube — initial setup"

    configure_vm_max_map_count
    create_volumes

    print_success "Setup complete. You can now start SonarQube with: docker compose up -d"
}

# ============================================================================
# Main
# ============================================================================

main "$@"