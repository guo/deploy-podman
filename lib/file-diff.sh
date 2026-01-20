#!/bin/bash

# File Diff and Smart Upload Module
# Uses rsync for efficient file comparison and upload, with diff preview for changed files
# Falls back to scp if rsync is not available

# Parse SSH_HOST to extract host and options
# SSH_HOST can be "user@host" or "user@host -i key -p 2222"
# Sets globals: SSH_HOST_ONLY, SSH_OPTIONS
parse_ssh_host() {
    local ssh_host="$1"

    # Split on first space to separate host from options
    SSH_HOST_ONLY="${ssh_host%% *}"
    if [[ "$ssh_host" == *" "* ]]; then
        SSH_OPTIONS="${ssh_host#* }"
    else
        SSH_OPTIONS=""
    fi
}

# Build rsync remote spec with proper SSH options
# Usage: build_rsync_cmd "source" "ssh_host" "dest"
# Returns command in RSYNC_CMD array
build_rsync_args() {
    local ssh_host="$1"
    parse_ssh_host "$ssh_host"

    RSYNC_SSH_ARGS=()
    if [ -n "$SSH_OPTIONS" ]; then
        RSYNC_SSH_ARGS=(-e "ssh $SSH_OPTIONS")
    fi
}

# Build scp args with SSH options normalized for scp
# Sets globals: SSH_HOST_ONLY, SCP_SSH_ARGS
build_scp_args() {
    local ssh_host="$1"
    local raw_opts=()
    local i=0

    parse_ssh_host "$ssh_host"
    SCP_SSH_ARGS=()

    if [ -z "$SSH_OPTIONS" ]; then
        return
    fi

    read -r -a raw_opts <<< "$SSH_OPTIONS"
    while [ $i -lt ${#raw_opts[@]} ]; do
        local opt="${raw_opts[$i]}"

        if [ "$opt" = "-p" ]; then
            SCP_SSH_ARGS+=("-P")
            if [ $((i + 1)) -lt ${#raw_opts[@]} ]; then
                SCP_SSH_ARGS+=("${raw_opts[$((i + 1))]}")
                i=$((i + 2))
                continue
            fi
        elif [[ "$opt" =~ ^-p[0-9]+$ ]]; then
            SCP_SSH_ARGS+=("-P${opt#-p}")
        else
            SCP_SSH_ARGS+=("$opt")
        fi
        i=$((i + 1))
    done
}

# List local items for dry-run fallback output
list_local_items() {
    local target_dir="$1"

    (cd "$target_dir" && find . -mindepth 1 -print | sed 's|^\./||' | sed 's/^/  /')
}

# Install rsync on remote server
# Usage: install_rsync_remote "$ssh_host"
install_rsync_remote() {
    local ssh_host="$1"

    echo "Installing rsync on remote server..."
    echo ""

    # Detect package manager and install rsync
    local install_cmd
    install_cmd=$(ssh $ssh_host 'sh -s' << 'EOF'
if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get update && apt-get install -y rsync"
elif command -v dnf >/dev/null 2>&1; then
    echo "dnf install -y rsync"
elif command -v yum >/dev/null 2>&1; then
    echo "yum install -y rsync"
elif command -v apk >/dev/null 2>&1; then
    echo "apk add --no-cache rsync"
elif command -v zypper >/dev/null 2>&1; then
    echo "zypper install -y rsync"
elif command -v pacman >/dev/null 2>&1; then
    echo "pacman -S --noconfirm rsync"
else
    echo ""
fi
EOF
)

    if [ -z "$install_cmd" ]; then
        echo "Error: Could not detect package manager on remote server"
        echo "Please install rsync manually on the remote server"
        return 1
    fi

    echo "Running: sudo sh -c '${install_cmd}'"
    if ! ssh $ssh_host "sudo sh -c '${install_cmd}'"; then
        echo "Error: Failed to install rsync"
        return 1
    fi

    # Verify installation
    if ssh $ssh_host "command -v rsync >/dev/null 2>&1"; then
        echo ""
        echo "✓ rsync installed successfully"
        return 0
    else
        echo "Error: rsync installation verification failed"
        return 1
    fi
}

# Check if rsync is available locally and remotely
# Sets globals: RSYNC_AVAILABLE ("true" or "false"), RSYNC_MISSING ("local", "remote", or "")
check_rsync_available() {
    local ssh_host="$1"

    RSYNC_MISSING=""

    # Check local rsync
    if ! command -v rsync >/dev/null 2>&1; then
        RSYNC_AVAILABLE="false"
        RSYNC_MISSING="local"
        return
    fi

    # Check remote rsync (use unquoted ssh_host for option expansion)
    if ! ssh $ssh_host "command -v rsync >/dev/null 2>&1"; then
        RSYNC_AVAILABLE="false"
        RSYNC_MISSING="remote"
        return
    fi

    RSYNC_AVAILABLE="true"
}

# Check if a file is binary (returns 0 for binary, 1 for text)
is_binary_file() {
    local file="$1"

    # Symlinks are not binary
    [ -L "$file" ] && return 1

    local mime_type
    mime_type=$(file --mime-type -b "$file" 2>/dev/null)

    case "$mime_type" in
        text/*|application/json|application/xml|application/javascript)
            return 1  # Text file
            ;;
        *)
            return 0  # Binary file
            ;;
    esac
}

# Show diff for a changed file
show_file_diff() {
    local local_file="$1"
    local ssh_host="$2"
    local remote_file="$3"
    local relative_name="$4"

    # Handle symlinks
    if [ -L "$local_file" ]; then
        local local_target remote_target
        local_target=$(readlink "$local_file")
        remote_target=$(ssh $ssh_host "readlink '$remote_file' 2>/dev/null" || echo "")
        echo "  symlink: $remote_target -> $local_target"
        return
    fi

    # Check if binary
    if is_binary_file "$local_file"; then
        echo "  (binary file differs)"
        return
    fi

    # Get remote file content (guard against read failures)
    local temp_remote
    temp_remote=$(mktemp)
    if ! ssh $ssh_host "cat '$remote_file'" > "$temp_remote" 2>/dev/null; then
        echo "  (unable to read remote file for diff)"
        rm -f "$temp_remote"
        return
    fi

    # Show diff (limit to 20 lines)
    echo "  --- remote"
    echo "  +++ local"
    diff -u "$temp_remote" "$local_file" 2>/dev/null | tail -n +3 | head -20 | sed 's/^/  /' || true

    local diff_lines
    diff_lines=$(diff -u "$temp_remote" "$local_file" 2>/dev/null | tail -n +3 | wc -l | tr -d ' ')
    if [ "$diff_lines" -gt 20 ]; then
        echo "  ... ($((diff_lines - 20)) more lines)"
    fi

    rm -f "$temp_remote"
}

# Fallback upload using scp (when rsync not available)
scp_upload_files() {
    local target_dir="$1"
    local ssh_host="$2"
    local remote_base_dir="$3"

    echo "Using scp for file upload (rsync not available)..."
    echo ""

    # Ensure remote directory exists (unquoted for option expansion)
    ssh $ssh_host "mkdir -p '$remote_base_dir'"

    # Parse SSH_HOST for scp (need host only for remote spec)
    build_scp_args "$ssh_host"

    # Upload all files (including hidden files)
    shopt -s dotglob nullglob
    local files=( "${target_dir}/"* )
    if [ ${#files[@]} -eq 0 ]; then
        echo "Warning: No files to upload (this is normal if directory is empty)"
        shopt -u dotglob nullglob
        return 0
    fi

    if ! scp "${SCP_SSH_ARGS[@]}" -r "${files[@]}" "${SSH_HOST_ONLY}:${remote_base_dir}/"; then
        shopt -u dotglob nullglob
        echo "Error: scp upload failed"
        return 1
    fi
    shopt -u dotglob nullglob

    echo "✓ Target files uploaded to ${remote_base_dir}"
}

# Main function: smart upload with rsync and per-file diff preview
# Usage: smart_upload_files "$TARGET_DIR" "$SSH_HOST" "$REMOTE_BASE_DIR" "$AUTO_CONFIRM" "$DRY_RUN"
smart_upload_files() {
    local target_dir="$1"
    local ssh_host="$2"
    local remote_base_dir="$3"
    local auto_confirm="${4:-false}"
    local dry_run="${5:-false}"

    # Check rsync availability
    check_rsync_available "$ssh_host"

    if [ "$RSYNC_AVAILABLE" != "true" ]; then
        if [ "$RSYNC_MISSING" = "remote" ]; then
            echo "rsync is not installed on the remote server."
            echo "Without rsync, file comparison is not available (will upload all files)."
            echo ""
            if [ "$dry_run" != "true" ] && [ "$auto_confirm" != "true" ]; then
                read -p "Install rsync on remote server now? (y/N): " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo ""
                    install_rsync_remote "$ssh_host"
                    # Re-check rsync availability
                    check_rsync_available "$ssh_host"
                    if [ "$RSYNC_AVAILABLE" = "true" ]; then
                        echo ""
                        echo "Continuing with rsync-based comparison..."
                        echo ""
                    fi
                else
                    echo ""
                    echo "Tip: Run 'shipd setup-rsync <target>' to enable file comparison"
                    echo ""
                fi
            else
                echo "Tip: Run 'shipd setup-rsync <target>' to enable file comparison"
                echo ""
            fi
        elif [ "$RSYNC_MISSING" = "local" ]; then
            echo "rsync is not installed locally. Install it with your package manager."
            echo "Without rsync, file comparison is not available (will upload all files)."
            echo ""
        fi

        if [ "$RSYNC_AVAILABLE" != "true" ]; then
            if [ "$dry_run" = "true" ]; then
                echo "DRY-RUN: Would upload all files via scp (rsync not available)"
                echo ""
                list_local_items "$target_dir"
                return 0
            fi
            scp_upload_files "$target_dir" "$ssh_host" "$remote_base_dir"
            return
        fi
    fi

    echo "Comparing files with remote server..."
    echo ""

    if [ "$dry_run" = "true" ]; then
        if ! ssh $ssh_host "[ -d '$remote_base_dir' ]" >/dev/null 2>&1; then
            echo "DRY-RUN: Remote directory does not exist; would upload all files"
            echo ""
            list_local_items "$target_dir"
            return 0
        fi
    else
        # Ensure remote directory exists (unquoted for option expansion)
        ssh $ssh_host "mkdir -p '$remote_base_dir'"
    fi

    # Build rsync args for SSH options
    build_rsync_args "$ssh_host"

    # Use rsync dry-run to get list of changes
    # -a = archive mode (preserves permissions, recursive, etc.)
    # -v = verbose
    # -n = dry-run
    # -i = itemize changes
    # --out-format = emit itemize + path only (avoid "-> target" in symlinks)
    local rsync_output rsync_stderr rsync_exit=0
    rsync_stderr=$(mktemp)
    rsync_output=$(rsync "${RSYNC_SSH_ARGS[@]}" -avi --dry-run --out-format='%i %n' "${target_dir}/" "${SSH_HOST_ONLY}:${remote_base_dir}/" 2>"$rsync_stderr") || rsync_exit=$?

    if [ "$rsync_exit" -ne 0 ]; then
        echo "Warning: rsync dry-run returned exit code $rsync_exit"
        if [ -s "$rsync_stderr" ]; then
            cat "$rsync_stderr" | head -3 | sed 's/^/  /'
        fi
        rm -f "$rsync_stderr"
        if [ "$dry_run" = "true" ]; then
            echo "DRY-RUN: Would upload all files via scp (rsync dry-run failed)"
            echo ""
            list_local_items "$target_dir"
            return 0
        else
            echo "Falling back to scp..."
            scp_upload_files "$target_dir" "$ssh_host" "$remote_base_dir"
            return
        fi
    fi
    rm -f "$rsync_stderr"

    # Parse rsync output to categorize files
    local new_files=()
    local changed_files=()
    local new_symlinks=()
    local changed_symlinks=()
    local unchanged_count=0

    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # rsync itemize format: YXcstpoguax path
        # Y = update type: < sent, > received, c local change, h hard link, . no update, * message
        # X = file type: f file, d directory, L symlink, etc.
        # The rest are attribute changes

        local item_flags="${line:0:11}"
        local file_path="${line:12}"

        # Skip directories (we'll handle them via rsync)
        [[ "${item_flags:1:1}" == "d" ]] && continue

        # Check if it's a file operation (>f)
        if [[ "$item_flags" =~ ^\>f ]]; then
            if [[ "$item_flags" == ">f+++++++++" ]]; then
                new_files+=("$file_path")
            else
                changed_files+=("$file_path")
            fi
        # Check if it's a symlink operation (>L or cL)
        elif [[ "$item_flags" =~ ^\>L ]] || [[ "$item_flags" =~ ^cL ]]; then
            if [[ "$item_flags" == ">L+++++++++" ]] || [[ "$item_flags" == "cL+++++++++" ]]; then
                new_symlinks+=("$file_path")
            else
                changed_symlinks+=("$file_path")
            fi
        fi
    done <<< "$rsync_output"

    # Count unchanged (total files/symlinks minus new and changed)
    local total_local_items
    total_local_items=$(find "$target_dir" \( -type f -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
    local total_changes=$((${#new_files[@]} + ${#changed_files[@]} + ${#new_symlinks[@]} + ${#changed_symlinks[@]}))
    unchanged_count=$((total_local_items - total_changes))

    # Track files to upload
    local files_to_upload=()
    local files_skipped=0

    # Process new files (no prompt needed)
    for file_path in "${new_files[@]}"; do
        echo "${file_path}: [NEW] Will upload"
        files_to_upload+=("$file_path")
    done

    # Process new symlinks (no prompt needed)
    for file_path in "${new_symlinks[@]}"; do
        local target
        target=$(readlink "${target_dir}/${file_path}")
        echo "${file_path}: [NEW SYMLINK] -> ${target}"
        files_to_upload+=("$file_path")
    done

    # Process changed files (show diff and prompt)
    for file_path in "${changed_files[@]}"; do
        local local_file="${target_dir}/${file_path}"
        local remote_file="${remote_base_dir}/${file_path}"

        echo "${file_path}: [CHANGED]"
        show_file_diff "$local_file" "$ssh_host" "$remote_file" "$file_path"

        # Auto-confirm if -y flag was provided
        if [ "$auto_confirm" = "true" ]; then
            echo "  Override remote file? (y/n): y (auto-confirmed)"
            echo "  ✓ Will upload ${file_path}"
            files_to_upload+=("$file_path")
        else
            # Prompt user
            echo ""
            read -p "  Override remote file? (y/n): " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "  ✓ Will upload ${file_path}"
                files_to_upload+=("$file_path")
            else
                echo "  ✗ Skipping ${file_path}"
                ((files_skipped++))
            fi
        fi
        echo ""
    done

    # Process changed symlinks (show diff and prompt)
    for file_path in "${changed_symlinks[@]}"; do
        local local_file="${target_dir}/${file_path}"
        local remote_file="${remote_base_dir}/${file_path}"

        echo "${file_path}: [CHANGED SYMLINK]"
        show_file_diff "$local_file" "$ssh_host" "$remote_file" "$file_path"

        # Auto-confirm if -y flag was provided
        if [ "$auto_confirm" = "true" ]; then
            echo "  Override remote symlink? (y/n): y (auto-confirmed)"
            echo "  ✓ Will upload ${file_path}"
            files_to_upload+=("$file_path")
        else
            # Prompt user
            echo ""
            read -p "  Override remote symlink? (y/n): " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "  ✓ Will upload ${file_path}"
                files_to_upload+=("$file_path")
            else
                echo "  ✗ Skipping ${file_path}"
                ((files_skipped++))
            fi
        fi
        echo ""
    done

    # Show unchanged files summary
    if [ $unchanged_count -gt 0 ]; then
        echo "(${unchanged_count} file(s) identical, skipping)"
        echo ""
    fi

    # Summary
    local total_upload=${#files_to_upload[@]}
    local total_skip=$((unchanged_count + files_skipped))
    local total_new=$((${#new_files[@]} + ${#new_symlinks[@]}))
    local total_changed=$((${#changed_files[@]} + ${#changed_symlinks[@]}))

    echo "========================================"
    echo "Upload summary: ${total_upload} file(s) to upload, ${total_skip} file(s) skipped"
    if [ $total_new -gt 0 ]; then
        echo "  New:       ${total_new}"
    fi
    if [ $total_changed -gt 0 ]; then
        local changed_upload=$((total_changed - files_skipped))
        echo "  Changed:   ${changed_upload} (${files_skipped} declined)"
    fi
    if [ $unchanged_count -gt 0 ]; then
        echo "  Identical: ${unchanged_count}"
    fi
    echo "========================================"
    echo ""

    # In dry-run mode, stop here without making changes
    if [ "$dry_run" = "true" ]; then
        return 0
    fi

    # Upload files using rsync
    if [ $total_upload -eq 0 ]; then
        # Still need to ensure directories exist
        echo "Syncing directory structure..."
        if ! rsync "${RSYNC_SSH_ARGS[@]}" -a --include='*/' --exclude='*' "${target_dir}/" "${SSH_HOST_ONLY}:${remote_base_dir}/"; then
            echo "Error: failed to sync directory structure"
            return 1
        fi
        echo "✓ No file changes to upload"
        return 0
    fi

    echo "Uploading ${total_upload} file(s)..."

    # If all files are to be uploaded (no skips), use rsync directly
    if [ $files_skipped -eq 0 ]; then
        local upload_stdout upload_stderr upload_exit=0
        upload_stdout=$(mktemp)
        upload_stderr=$(mktemp)
        rsync "${RSYNC_SSH_ARGS[@]}" -av "${target_dir}/" "${SSH_HOST_ONLY}:${remote_base_dir}/" 1>"$upload_stdout" 2>"$upload_stderr" || upload_exit=$?

        if [ "$upload_exit" -ne 0 ]; then
            echo "Error: rsync upload failed (exit code $upload_exit)"
            if [ -s "$upload_stderr" ]; then
                cat "$upload_stderr" | head -3 | sed 's/^/  /'
            fi
            rm -f "$upload_stdout" "$upload_stderr"
            return 1
        fi

        grep -v "^$" "$upload_stdout" | grep -v "sending incremental" | grep -v "sent .* bytes" | grep -v "total size" | head -20
        rm -f "$upload_stdout" "$upload_stderr"
        echo ""
        echo "✓ All files uploaded to ${remote_base_dir}"
    else
        # Upload only selected files
        # First sync directory structure
        if ! rsync "${RSYNC_SSH_ARGS[@]}" -a --include='*/' --exclude='*' "${target_dir}/" "${SSH_HOST_ONLY}:${remote_base_dir}/"; then
            echo "Error: failed to sync directory structure"
            return 1
        fi

        # Then upload each selected file
        local upload_failures=0
        for file_path in "${files_to_upload[@]}"; do
            local local_file="${target_dir}/${file_path}"

            if ! rsync "${RSYNC_SSH_ARGS[@]}" -a "$local_file" "${SSH_HOST_ONLY}:${remote_base_dir}/${file_path}"; then
                echo "  ✗ Failed to upload: ${file_path}"
                upload_failures=$((upload_failures + 1))
            else
                echo "  ✓ Uploaded: ${file_path}"
            fi
        done
        if [ "$upload_failures" -gt 0 ]; then
            echo "Error: ${upload_failures} file(s) failed to upload"
            return 1
        fi
        echo ""
        echo "✓ Selected files uploaded to ${remote_base_dir}"
    fi
}
