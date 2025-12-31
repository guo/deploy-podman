#!/bin/bash

# Backward compatibility wrapper for deploy-podman-ssh.sh
# This script delegates to the new unified deploy-ssh.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the unified deployment script
exec "${SCRIPT_DIR}/deploy-ssh.sh" "$@"
