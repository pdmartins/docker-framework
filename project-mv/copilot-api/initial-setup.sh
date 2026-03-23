#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: initial-setup.sh
# Description: Prepares the host environment for running copilot-api platform
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

# Script directory (platform/copilot-api/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Error handling
trap 'print_error "Error on line $LINENO"; exit 1' ERR

# ============================================================================
# Functions
# ============================================================================

create_volumes() {
    local volumes_dir="${SCRIPT_DIR}/volumes"
    local target="${volumes_dir}/data"

    print_info "Ensuring volume directory exists: ${target}"

    if [[ -d "${target}" ]]; then
        print_warning "Already exists: ${target}"
    else
        mkdir -p "${target}"
        print_success "Created: ${target}"
    fi
}

print_auth_instructions() {
    echo ""
    print_info "Authentication options after starting the service:"
    echo ""
    echo "  Opção A — GH_TOKEN (recomendada para automação):"
    echo "    GH_TOKEN=ghp_SEU_TOKEN claude-proxy enable"
    echo ""
    echo "  Opção B — OAuth interativo (credenciais persistem no volume):"
    echo "    claude-proxy auth"
    echo ""
    print_info "Toggle Claude Code entre copilot-api e Anthropic direto:"
    echo ""
    echo "    claude-proxy enable    # → usa GitHub Copilot via localhost:4141"
    echo "    claude-proxy disable   # → volta para Anthropic direto"
    echo "    claude-proxy status    # → exibe modo atual"
    echo ""
}

main() {
    print_step "copilot-api — initial setup"

    create_volumes
    print_auth_instructions

    print_success "Setup completo. Use 'claude-proxy enable' para iniciar e configurar."
}

# ============================================================================
# Main
# ============================================================================

main "$@"
