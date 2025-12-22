#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check if targets directory exists
if [ ! -d "${SCRIPT_DIR}/targets" ]; then
    print_error "targets/ directory not found in ${SCRIPT_DIR}"
    echo ""
    echo "Please create target directories first:"
    echo "  1. mkdir -p targets/myapp"
    echo "  2. cp .config.example targets/myapp/.config"
    echo "  3. cp env.example targets/myapp/.env"
    echo "  4. Edit the config and env files"
    echo ""
    exit 1
fi

# Function to get all targets from targets directory
get_targets() {
    for dir in "${SCRIPT_DIR}/targets"/*/ ; do
        if [ -d "$dir" ]; then
            basename "$dir"
        fi
    done
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <TARGETS...>"
    echo ""
    echo "Deploy to multiple targets"
    echo ""
    echo "Options:"
    echo "  --all              Deploy to all configured targets"
    echo "  -p, --parallel     Deploy in parallel (faster)"
    echo "  -s, --sequential   Deploy sequentially (default)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all                     # Deploy to all targets (with confirmation)"
    echo "  $0 --all --parallel          # Deploy to all targets in parallel"
    echo "  $0 staging production        # Deploy to staging and production"
    echo "  $0 -p staging production     # Deploy to staging and production in parallel"
    echo ""
    echo "Available targets:"
    get_targets | sed 's/^/  - /'
}

# Parse arguments
PARALLEL=false
DEPLOY_ALL=false
TARGETS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DEPLOY_ALL=true
            shift
            ;;
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -s|--sequential)
            PARALLEL=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

# If --all flag is set, get all targets
if [ "$DEPLOY_ALL" = true ]; then
    mapfile -t TARGETS < <(get_targets)
fi

# If no targets specified and --all not used, show usage and exit
if [ ${#TARGETS[@]} -eq 0 ]; then
    show_usage
    exit 1
fi

echo "========================================="
echo "Multi-Target Deployment"
echo "========================================="
echo "Mode: $([ "$PARALLEL" = true ] && echo "Parallel" || echo "Sequential")"
echo ""

# If deploying to all, show the list and require confirmation
if [ "$DEPLOY_ALL" = true ]; then
    echo "Deploying to ALL targets:"
    for target in "${TARGETS[@]}"; do
        echo "  - ${target}"
    done
    echo ""
fi

echo "Targets to deploy: ${TARGETS[*]}"
echo ""

# Ask for confirmation
read -p "Continue with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled"
    exit 0
fi

# Track deployment results
DEPLOYMENT_PIDS=()

# Function to deploy to a single target
deploy_target() {
    local target=$1
    local log_file="${SCRIPT_DIR}/deploy-${target}.log"

    print_info "Starting deployment to ${target}..."

    if "${SCRIPT_DIR}/deploy-podman-ssh.sh" "$target" 2>&1 | tee "$log_file"; then
        echo "SUCCESS" > "${SCRIPT_DIR}/.deploy-${target}.result"
        print_success "Deployment to ${target} completed successfully"
        return 0
    else
        echo "FAILED" > "${SCRIPT_DIR}/.deploy-${target}.result"
        print_error "Deployment to ${target} failed (see ${log_file} for details)"
        return 1
    fi
}

# Deploy based on mode
START_TIME=$(date +%s)

if [ "$PARALLEL" = true ]; then
    print_info "Deploying to all targets in parallel..."
    echo ""

    # Start all deployments in background
    for target in "${TARGETS[@]}"; do
        deploy_target "$target" &
        DEPLOYMENT_PIDS+=($!)
    done

    # Wait for all deployments to complete
    for pid in "${DEPLOYMENT_PIDS[@]}"; do
        wait $pid || true
    done
else
    print_info "Deploying to targets sequentially..."
    echo ""

    # Deploy one by one
    for target in "${TARGETS[@]}"; do
        deploy_target "$target"
        echo ""
    done
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Print summary
echo ""
echo "========================================="
echo "Deployment Summary"
echo "========================================="
echo "Total time: ${DURATION} seconds"
echo ""

SUCCESS_COUNT=0
FAILED_COUNT=0

for target in "${TARGETS[@]}"; do
    result_file="${SCRIPT_DIR}/.deploy-${target}.result"
    if [ -f "$result_file" ] && [ "$(cat "$result_file")" = "SUCCESS" ]; then
        echo -e "  ${GREEN}✓${NC} ${target}"
        ((SUCCESS_COUNT++))
        rm -f "$result_file"
    else
        echo -e "  ${RED}✗${NC} ${target} (see deploy-${target}.log)"
        ((FAILED_COUNT++))
        rm -f "$result_file"
    fi
done

echo ""
echo "Success: ${SUCCESS_COUNT} | Failed: ${FAILED_COUNT}"
echo ""

# Exit with error if any deployment failed
if [ $FAILED_COUNT -gt 0 ]; then
    print_error "Some deployments failed!"
    exit 1
else
    print_success "All deployments completed successfully!"
    exit 0
fi
