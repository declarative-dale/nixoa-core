#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# NiXOA - Command Line Interface

set -euo pipefail

VERSION="1.2.0"

# Resolve config directory with proper sudo handling
if [ -n "${SUDO_USER:-}" ]; then
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    CONFIG_DIR="${REAL_HOME}/system"
else
    CONFIG_DIR="${HOME}/system"
fi
CONFIG_FILES=(configuration.nix config config.nixoa.toml)
IDENTITY_FILE="${CONFIG_DIR}/config/host.nix"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Show usage
show_usage() {
    cat <<EOF
NiXOA - Command Line Interface v${VERSION}

USAGE:
    nixoa <command> [options]

CONFIGURATION COMMANDS:
    config commit <message>     Commit configuration changes
    config apply <message>      Commit and rebuild system
    config show                 Show uncommitted configuration changes
    config diff                 Alias for 'config show'
    config history              View configuration change history
    config edit                 Edit configuration files
    config status               Show git status of config repo

SYSTEM COMMANDS:
    rebuild [test|switch]       Rebuild NiXOA system (default: switch)
    update                      Update flake inputs and rebuild
    rollback                    Rollback to previous generation
    list-generations            List available system generations

INFORMATION COMMANDS:
    status                      Show NiXOA system status
    version                     Show version information
    help                        Show this help message

EXAMPLES:
    nixoa config edit                      # Edit configuration
    nixoa config show                      # See what changed
    nixoa config commit "Updated ports"    # Commit changes
    nixoa config apply "Updated ports"     # Commit and rebuild
    nixoa rebuild                          # Rebuild system
    nixoa update                           # Update all inputs

For more information, visit: https://codeberg.org/NiXOA/core
EOF
}

# Config: Commit changes
config_commit() {
    if [ $# -eq 0 ]; then
        print_error "Commit message required"
        echo "Usage: nixoa config commit <message>"
        exit 1
    fi

    local message="$1"

    cd "$CONFIG_DIR" || {
        print_error "Config directory not found: $CONFIG_DIR"
        exit 1
    }

    # Initialize git if needed
    if [ ! -d .git ]; then
        print_info "Initializing git repository..."
        git init
        git add .
        git commit -m "Initial commit"
    fi

    # Show what's changed
    if ! git diff --quiet "${CONFIG_FILES[@]}" 2>/dev/null; then
        print_info "Configuration changes:"
        git diff --stat "${CONFIG_FILES[@]}" 2>/dev/null || true
        echo ""
    fi

    # Stage the configuration files
    git add "${CONFIG_FILES[@]}"

    # Check if there are changes to commit
    if git diff --staged --quiet; then
        print_warning "No changes to commit"
        exit 0
    fi

    # Commit the changes
    git commit -m "$message"
    print_success "Configuration committed: $message"
}

# Config: Apply (commit + rebuild)
config_apply() {
    if [ $# -eq 0 ]; then
        message="Update configuration [$(date '+%Y-%m-%d %H:%M:%S')]"
    else
        message="$1"
    fi

    print_info "Committing configuration changes..."
    config_commit "$message"

    echo ""
    print_info "Rebuilding NiXOA CE system..."
    rebuild_system "switch"
}

# Config: Show diff
config_show() {
    cd "$CONFIG_DIR" || {
        print_error "Config directory not found: $CONFIG_DIR"
        exit 1
    }

    if [ ! -d .git ]; then
        print_warning "Git repository not initialized"
        exit 1
    fi

    print_info "Uncommitted configuration changes:"
    echo ""

    if git diff --quiet "${CONFIG_FILES[@]}"; then
        print_success "No uncommitted changes"
    else
        git diff "${CONFIG_FILES[@]}"
    fi
}

# Config: Show history
config_history() {
    cd "$CONFIG_DIR" || {
        print_error "Config directory not found: $CONFIG_DIR"
        exit 1
    }

    if [ ! -d .git ]; then
        print_warning "Git repository not initialized"
        exit 1
    fi

    print_info "Configuration change history:"
    echo ""
    git log --oneline --decorate --graph -10 -- "${CONFIG_FILES[@]}"

    echo ""
    print_info "To see full diff: git show <commit-hash>"
    print_info "To revert: cd $CONFIG_DIR && git checkout <commit-hash> -- ${CONFIG_FILES[*]}"
}

# Config: Edit files
config_edit() {
    cd "$CONFIG_DIR" || {
        print_error "Config directory not found: $CONFIG_DIR"
        exit 1
    }

    local editor="${EDITOR:-nano}"

    print_info "Opening configuration files in $editor..."
    echo ""
    echo "Files:"
    echo "  1. config/ (all config/*.nix)"
    echo "  2. config.nixoa.toml"
    echo "  3. configuration.nix"
    echo ""

    read -r -p "Which file to edit? [1/2/3/all] (default: 1): " choice

    case "${choice:-1}" in
        1)
            $editor config/*.nix
            ;;
        2)
            $editor config.nixoa.toml
            ;;
        3)
            $editor configuration.nix
            ;;
        all|a)
            $editor config/*.nix config.nixoa.toml
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    print_info "After editing, run:"
    print_info "  nixoa config show     # Review changes"
    print_info "  nixoa config apply \"Your message\"  # Apply changes"
}

# Config: Git status
config_status() {
    cd "$CONFIG_DIR" || {
        print_error "Config directory not found: $CONFIG_DIR"
        exit 1
    }

    if [ ! -d .git ]; then
        print_warning "Git repository not initialized"
        exit 1
    fi

    print_info "Configuration repository status:"
    echo ""
    git status
}

# Rebuild system
rebuild_system() {
    local mode="${1:-switch}"

    if [[ ! "$mode" =~ ^(switch|test|boot)$ ]]; then
        print_error "Invalid rebuild mode: $mode"
        echo "Valid modes: switch, test, boot"
        exit 1
    fi

    cd "$CONFIG_DIR" || {
        print_error "System config directory not found: $CONFIG_DIR"
        exit 1
    }

    # Read hostname from config/host.nix (defaults to "nixoa" if not set)
    CONFIG_HOSTNAME=$(grep -E "^[[:space:]]*hostname[[:space:]]*=" "$IDENTITY_FILE" 2>/dev/null | sed 's/.*= *\"\\(.*\\)\".*/\\1/' | head -1)
    CONFIG_HOSTNAME="${CONFIG_HOSTNAME:-nixoa}"

    print_info "Running: sudo nixos-rebuild $mode --flake .#${CONFIG_HOSTNAME}"

    if sudo nixos-rebuild "$mode" --flake ".#${CONFIG_HOSTNAME}"; then
        print_success "System rebuilt successfully!"

        if [ "$mode" = "switch" ]; then
            print_info "New configuration is active"
        elif [ "$mode" = "test" ]; then
            print_warning "Configuration is active but will not persist after reboot"
        elif [ "$mode" = "boot" ]; then
            print_info "Configuration will activate on next boot"
        fi
    else
        print_error "Rebuild failed!"
        exit 1
    fi
}

# Update flake inputs
update_flake() {
    cd "$CONFIG_DIR" || {
        print_error "System config directory not found: $CONFIG_DIR"
        exit 1
    }

    print_info "Updating flake inputs..."

    if nix flake update; then
        print_success "Flake inputs updated"
        echo ""
        print_info "Updated inputs:"
        git diff flake.lock 2>/dev/null || true
        echo ""

        read -p "Rebuild system with updated inputs? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rebuild_system "switch"
        else
            print_info "Run 'nixoa rebuild' when ready to apply updates"
        fi
    else
        print_error "Failed to update flake inputs"
        exit 1
    fi
}

# Rollback to previous generation
rollback_system() {
    print_info "Rolling back to previous generation..."

    if sudo nixos-rebuild switch --rollback; then
        print_success "Rolled back to previous generation"
    else
        print_error "Rollback failed!"
        exit 1
    fi
}

# List system generations
list_generations() {
    print_info "Available NixOS generations:"
    echo ""
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system
}

# Show system status
show_status() {
    print_info "NiXOA CE System Status"
    echo ""

    echo "System Information:"
    echo "  Hostname: $(hostname)"
    echo "  NixOS Version: $(nixos-version)"
    echo "  Kernel: $(uname -r)"
    echo ""

    echo "Service Status:"
    systemctl is-active xo-server.service >/dev/null 2>&1 && \
        echo -e "  xo-server: ${GREEN}active${NC}" || \
        echo -e "  xo-server: ${RED}inactive${NC}"

    systemctl is-active redis-xo.service >/dev/null 2>&1 && \
        echo -e "  redis-xo:  ${GREEN}active${NC}" || \
        echo -e "  redis-xo:  ${RED}inactive${NC}"
    echo ""

    echo "Configuration:"
    echo "  Config:   $CONFIG_DIR"

    if [ -d "$CONFIG_DIR/.git" ]; then
        cd "$CONFIG_DIR"
        local last_commit
        last_commit=$(git log -1 --oneline -- "${CONFIG_FILES[@]}" 2>/dev/null | head -1)
        if [ -n "$last_commit" ]; then
            echo "  Last config change: $last_commit"
        fi
    fi
}

# Show version
show_version() {
    echo "NiXOA CE CLI v${VERSION}"
    echo "NixOS Version: $(nixos-version)"
}

# Main command dispatcher
main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        config)
            if [ $# -eq 0 ]; then
                print_error "Config subcommand required"
                echo "Try: nixoa config help"
                exit 1
            fi

            local subcommand="$1"
            shift

            case "$subcommand" in
                commit)
                    config_commit "$@"
                    ;;
                apply)
                    config_apply "$@"
                    ;;
                show|diff)
                    config_show
                    ;;
                history)
                    config_history
                    ;;
                edit)
                    config_edit
                    ;;
                status)
                    config_status
                    ;;
                help)
                    show_usage
                    ;;
                *)
                    print_error "Unknown config subcommand: $subcommand"
                    echo "Try: nixoa config help"
                    exit 1
                    ;;
            esac
            ;;

        rebuild)
            rebuild_system "${1:-switch}"
            ;;

        update)
            update_flake
            ;;

        rollback)
            rollback_system
            ;;

        list-generations|generations)
            list_generations
            ;;

        status)
            show_status
            ;;

        version|--version|-v)
            show_version
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            print_error "Unknown command: $command"
            echo "Try: nixoa help"
            exit 1
            ;;
    esac
}

main "$@"
