#!/bin/bash

set -e

# Auto-detect development vs installed mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d "${SCRIPT_DIR}/lib" ]; then
    # Development mode: Running from repo (./shipd.sh or repo checkout)
    LIB_DIR="${SCRIPT_DIR}/lib"
elif [ -d "/opt/homebrew/lib/shipd" ]; then
    # Homebrew (Apple Silicon): /opt/homebrew/bin/shipd
    LIB_DIR="/opt/homebrew/lib/shipd"
elif [ -d "/usr/local/lib/shipd" ]; then
    # Homebrew (Intel) or manual install: /usr/local/bin/shipd
    LIB_DIR="/usr/local/lib/shipd"
else
    print_error "Cannot find lib directory"
    echo "  - Development: Expected ${SCRIPT_DIR}/lib/"
    echo "  - Installed: Expected /usr/local/lib/shipd/ or /opt/homebrew/lib/shipd/"
    exit 1
fi

# Version
VERSION="1.0.11"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Show main help
show_help() {
    echo -e "${BOLD}Shipd${NC} - Container deployment automation tool"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    shipd <COMMAND> [OPTIONS] [ARGS]"
    echo ""
    echo -e "${BOLD}COMMANDS:${NC}"
    echo -e "    ${CYAN}deploy${NC}         Deploy a single target"
    echo -e "    ${CYAN}deploy-multi${NC}   Deploy to multiple targets"
    echo -e "    ${CYAN}stop${NC}           Stop a deployed target"
    echo -e "    ${CYAN}logs${NC}           Show container logs in follow mode"
    echo -e "    ${CYAN}restart${NC}        Restart a container"
    echo -e "    ${CYAN}inspect${NC}        Inspect a deployed container's runtime info"
    echo -e "    ${CYAN}setup-caddy${NC}    Setup Caddy reverse proxy for a target"
    echo -e "    ${CYAN}setup-rsync${NC}    Install rsync on remote server"
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help     Show help for a command"
    echo "    -v, --version  Show version"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    # Deploy latest version to a target"
    echo "    shipd deploy myapp-prod"
    echo ""
    echo "    # Deploy specific version"
    echo "    shipd deploy myapp-prod v1.2.3"
    echo ""
    echo "    # Deploy with auto-confirm"
    echo "    shipd deploy -y myapp-prod"
    echo ""
    echo "    # Deploy to multiple targets"
    echo "    shipd deploy-multi staging production"
    echo ""
    echo "    # Deploy to all targets in parallel"
    echo "    shipd deploy-multi --all --parallel"
    echo ""
    echo "    # Stop a deployed target"
    echo "    shipd stop myapp-prod"
    echo ""
    echo "    # Stop and remove a target"
    echo "    shipd stop myapp-prod --remove"
    echo ""
    echo "    # Setup Caddy for zero-downtime deployments"
    echo "    shipd setup-caddy myapp-prod"
    echo ""
    echo "    # Install rsync on remote server for file comparison"
    echo "    shipd setup-rsync myapp-prod"
    echo ""
    echo "    # Inspect a deployed container"
    echo "    shipd inspect depinscan"
    echo ""
    echo "    # Follow container logs"
    echo "    shipd logs myapp-prod"
    echo ""
    echo "    # Restart a container"
    echo "    shipd restart myapp-prod"
    echo ""
    echo -e "${BOLD}GET HELP:${NC}"
    echo "    shipd deploy --help"
    echo "    shipd deploy-multi --help"
    echo "    shipd stop --help"
    echo "    shipd logs --help"
    echo "    shipd restart --help"
    echo "    shipd inspect --help"
    echo "    shipd setup-caddy --help"
    echo "    shipd setup-rsync --help"
    echo ""
    echo -e "${BOLD}MORE INFO:${NC}"
    echo "    Documentation: https://github.com/guo/shipd"
    echo "    Report issues: https://github.com/guo/shipd/issues"
    echo ""
}

# Show version
show_version() {
    echo "Shipd v${VERSION}"
}

# Main command dispatcher
case "${1:-}" in
    deploy)
        shift
        exec "${LIB_DIR}/cmd-deploy.sh" "$@"
        ;;
    deploy-multi)
        shift
        exec "${LIB_DIR}/cmd-deploy-multi.sh" "$@"
        ;;
    stop)
        shift
        exec "${LIB_DIR}/cmd-stop.sh" "$@"
        ;;
    setup-caddy)
        shift
        exec "${LIB_DIR}/cmd-setup-caddy.sh" "$@"
        ;;
    setup-rsync)
        shift
        exec "${LIB_DIR}/cmd-setup-rsync.sh" "$@"
        ;;
    inspect)
        shift
        exec "${LIB_DIR}/cmd-inspect.sh" "$@"
        ;;
    logs)
        shift
        exec "${LIB_DIR}/cmd-logs.sh" "$@"
        ;;
    restart)
        shift
        exec "${LIB_DIR}/cmd-restart.sh" "$@"
        ;;
    -v|--version|version)
        show_version
        exit 0
        ;;
    -h|--help|help|"")
        show_help
        exit 0
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        echo "Run 'shipd --help' for usage."
        exit 1
        ;;
esac
