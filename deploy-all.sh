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

# Function to get all environments from config
get_environments() {
    grep -E '^\[.*\]$' "${SCRIPT_DIR}/deploy.config" | sed 's/\[\(.*\)\]/\1/'
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [ENVIRONMENTS...]"
    echo ""
    echo "Deploy to multiple environments at once"
    echo ""
    echo "Options:"
    echo "  -p, --parallel     Deploy to all environments in parallel (faster)"
    echo "  -s, --sequential   Deploy to all environments sequentially (default)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy to all environments sequentially"
    echo "  $0 --parallel                # Deploy to all environments in parallel"
    echo "  $0 staging production        # Deploy only to staging and production"
    echo "  $0 -p development staging    # Deploy to dev and staging in parallel"
    echo ""
    echo "Available environments:"
    get_environments | sed 's/^/  - /'
}

# Parse arguments
PARALLEL=false
ENVIRONMENTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
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
            ENVIRONMENTS+=("$1")
            shift
            ;;
    esac
done

# If no environments specified, use all
if [ ${#ENVIRONMENTS[@]} -eq 0 ]; then
    mapfile -t ENVIRONMENTS < <(get_environments)
fi

echo "========================================="
echo "Deploy All - Multi-Environment Deployment"
echo "========================================="
echo "Mode: $([ "$PARALLEL" = true ] && echo "Parallel" || echo "Sequential")"
echo "Environments: ${ENVIRONMENTS[*]}"
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

# Function to deploy to a single environment
deploy_environment() {
    local env=$1
    local log_file="${SCRIPT_DIR}/deploy-${env}.log"

    print_info "Starting deployment to ${env}..."

    if "${SCRIPT_DIR}/deploy-podman-ssh.sh" "$env" 2>&1 | tee "$log_file"; then
        echo "SUCCESS" > "${SCRIPT_DIR}/.deploy-${env}.result"
        print_success "Deployment to ${env} completed successfully"
        return 0
    else
        echo "FAILED" > "${SCRIPT_DIR}/.deploy-${env}.result"
        print_error "Deployment to ${env} failed (see ${log_file} for details)"
        return 1
    fi
}

# Deploy based on mode
START_TIME=$(date +%s)

if [ "$PARALLEL" = true ]; then
    print_info "Deploying to all environments in parallel..."
    echo ""

    # Start all deployments in background
    for env in "${ENVIRONMENTS[@]}"; do
        deploy_environment "$env" &
        DEPLOYMENT_PIDS+=($!)
    done

    # Wait for all deployments to complete
    for pid in "${DEPLOYMENT_PIDS[@]}"; do
        wait $pid || true
    done
else
    print_info "Deploying to environments sequentially..."
    echo ""

    # Deploy one by one
    for env in "${ENVIRONMENTS[@]}"; do
        deploy_environment "$env"
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

for env in "${ENVIRONMENTS[@]}"; do
    result_file="${SCRIPT_DIR}/.deploy-${env}.result"
    if [ -f "$result_file" ] && [ "$(cat "$result_file")" = "SUCCESS" ]; then
        echo -e "  ${GREEN}✓${NC} ${env}"
        ((SUCCESS_COUNT++))
        rm -f "$result_file"
    else
        echo -e "  ${RED}✗${NC} ${env} (see deploy-${env}.log)"
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
