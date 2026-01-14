#!/bin/bash

# Image Hash Checking Module
# This module provides functions to check if deployed image hash matches target image

# Check if image hash has changed
# Returns: 0 if hash changed (deploy needed), 1 if hash unchanged (skip deploy)
# Usage: check_image_hash_changed "podman|docker" "container_name" "target_image"
check_image_hash_changed() {
    local engine="$1"
    local container_name="$2"
    local target_image="$3"

    echo "Checking if image has changed..."

    # Check if container exists
    local container_exists
    container_exists=$(ssh ${SSH_HOST} "$engine ps -a --format '{{.Names}}' | grep -c '^$container_name\$' || true")

    if [ "$container_exists" -eq 0 ]; then
        echo "  → Container doesn't exist yet (first deployment)"
        return 0  # Deploy needed
    fi

    # Get current running container's image digest
    echo "  → Getting current container image digest..."
    local current_digest
    current_digest=$(ssh ${SSH_HOST} "$engine inspect $container_name --format='{{.Image}}' 2>/dev/null || echo ''")

    if [ -z "$current_digest" ]; then
        echo "  → Could not get current image digest"
        return 0  # Deploy needed (safer to deploy if we can't check)
    fi

    # Get target image digest (check if image exists locally on remote)
    echo "  → Querying for target image digest..."
    local target_digest
    target_digest=$(ssh ${SSH_HOST} "$engine inspect --format='{{.Id}}' $target_image 2>/dev/null || echo ''")

    # If target image not cached locally, we need to pull to check
    if [ -z "$target_digest" ]; then
        echo "  → Target image not cached locally, will pull to check"
        return 0  # Deploy needed (must pull to get new image)
    fi

    # Compare digests
    echo "  → Current: ${current_digest:0:19}"
    echo "  → Target:  ${target_digest:0:19}"

    if [ "$current_digest" = "$target_digest" ]; then
        echo "  ✓ Image hash unchanged - deployment not needed"
        return 1  # Skip deploy
    else
        echo "  → Image hash changed - deployment needed"
        return 0  # Deploy needed
    fi
}

# Check if compose images have changed
# Returns: 0 if any image changed (deploy needed), 1 if all unchanged (skip deploy)
# Usage: check_compose_images_changed "compose_file"
check_compose_images_changed() {
    local compose_file="$1"

    echo "Checking if compose images have changed..."

    # Get list of running containers for this compose project
    # Read into array to handle multiple containers properly
    local containers=()
    while IFS= read -r line; do
        [ -n "$line" ] && containers+=("$line")
    done < <(ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f $compose_file ps -q 2>/dev/null")

    if [ ${#containers[@]} -eq 0 ]; then
        echo "  → No running containers found (first deployment)"
        return 0  # Deploy needed
    fi

    echo "  → Found ${#containers[@]} running container(s)"
    echo ""

    local any_changed=false

    # Check each container
    for container_id in "${containers[@]}"; do
        [ -z "$container_id" ] && continue

        # Get container name
        local container_name
        container_name=$(ssh ${SSH_HOST} "docker inspect $container_id --format='{{.Name}}' 2>/dev/null | sed 's|^/||' || echo ''")

        if [ -n "$container_name" ]; then
            echo "  → Checking container: $container_name (${container_id:0:12})"
        else
            echo "  → Checking container: ${container_id:0:12}"
        fi

        # Get current image digest for this container
        local current_digest
        current_digest=$(ssh ${SSH_HOST} "docker inspect $container_id --format='{{.Image}}' 2>/dev/null || echo ''")

        if [ -z "$current_digest" ]; then
            echo "    Could not get current digest"
            any_changed=true
            continue
        fi

        # Get the image name used by this container
        local current_image
        current_image=$(ssh ${SSH_HOST} "docker inspect $container_id --format='{{.Config.Image}}' 2>/dev/null || echo ''")

        if [ -z "$current_image" ]; then
            echo "    Could not get image name"
            any_changed=true
            continue
        fi

        # Get the latest pulled image digest for the same image name
        local target_digest
        target_digest=$(ssh ${SSH_HOST} "docker inspect --format='{{.Id}}' '$current_image' 2>/dev/null || echo ''")

        if [ -z "$target_digest" ]; then
            echo "    Target image not found"
            any_changed=true
            continue
        fi

        echo "    Current: ${current_digest:0:19}"
        echo "    Target:  ${target_digest:0:19}"

        if [ "$current_digest" != "$target_digest" ]; then
            echo "    Image changed"
            any_changed=true
        else
            echo "    Image unchanged"
        fi
        echo ""
    done

    if [ "$any_changed" = true ]; then
        echo "  → At least one image changed - deployment needed"
        return 0  # Deploy needed
    else
        echo "  ✓ All images unchanged - deployment not needed"
        return 1  # Skip deploy
    fi
}
