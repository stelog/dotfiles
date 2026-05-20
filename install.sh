#!/usr/bin/env sh
#
# install.sh - Dotfiles installer
#
# Creates symlinks from this repository into a target "home" directory so that
# tools pick up their configuration from the repo. By default the target is
# $HOME, but it can be overridden (e.g. for testing). Each dotfiles category
# maps to a target directory:
#
#   bash/, git/, nano/, tmux/, vim/  ->  $HOME
#
# If a target path already exists (real file or symlink) the file is skipped
# and a warning is printed. Use --try-run (-n / --dry-run) to preview all
# actions without touching the filesystem.
#
# Compatible with bash and zsh.
#

set -u

DRY_RUN=0
FORCE=0
TARGET_HOME=

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Create symlinks from this repository into your HOME (or a specified directory).

Options:
  -n, --dry-run, --try-run  Print actions without changing files
  -f, --force               Overwrite existing files (a .bak backup is created first)
    --home, --target DIR      Install into DIR instead of $HOME (useful for testing)
  -h, --help                Show this help message
EOF
}

log_info() {
    printf 'INFO: %s\n' "$1"
}

log_warn() {
    printf 'WARN: %s\n' "$1" >&2
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: %s\n' "$*"
    else
        "$@"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -n|--dry-run|--try-run)
            DRY_RUN=1
            ;;
        -f|--force)
            FORCE=1
            ;;
        --home|--target)
            if [ "$#" -lt 2 ]; then
                log_warn "$1 requires a directory argument"
                usage
                exit 1
            fi
            TARGET_HOME=$2
            shift 2
            continue
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_warn "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
HOME_DIR=${TARGET_HOME:-${HOME:-}}

if [ -z "$HOME_DIR" ]; then
    log_warn "HOME is not set."
    exit 1
fi

run_cmd mkdir -p "$HOME_DIR"

backup_file() {
    target=$1
    backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
    run_cmd mv "$target" "$backup"
    if [ "$DRY_RUN" -eq 0 ]; then
        log_info "Backed up: $target -> $backup"
    fi
}

link_file() {
    src=$1
    dest=$2

    run_cmd mkdir -p "$(dirname -- "$dest")"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$FORCE" -ne 1 ]; then
            log_warn "Target exists, skipping: $dest"
            return 0
        fi
        backup_file "$dest"
        run_cmd rm -f "$dest"
    fi

    run_cmd ln -s "$src" "$dest"
    if [ "$DRY_RUN" -eq 0 ]; then
        log_info "Linked: $dest -> $src"
    fi
}

link_tree() {
    source_root=$1
    target_root=$2
    add_dot=${3:-0}

    if [ ! -d "$source_root" ]; then
        log_info "Skipping missing source directory: $source_root"
        return 0
    fi

    find "$source_root" -type f | while IFS= read -r src; do
        rel=${src#"$source_root"/}

        if [ "$add_dot" -eq 1 ]; then
            dir=$(dirname "$rel")
            base=$(basename "$rel")
            if [ "$dir" = "." ]; then
                rel=".${base}"
            else
                rel="${dir}/.${base}"
            fi
        fi

        link_file "$src" "$target_root/$rel"
    done
}

configure_git() {
    git_cfg="$HOME_DIR/.gitconfig"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: prompt whether to update %s\n' "$git_cfg"
        return 0
    fi

    printf '\nUpdate %s? [y/N] ' "$git_cfg"
    read -r answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *) log_info "Skipping git identity setup."; return 0 ;;
    esac

    printf '\n--- Git identity setup ---\n'
    printf 'Full name  : '
    read -r git_name
    printf 'Email      : '
    read -r git_email

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_warn "One or more fields are empty — skipping git identity setup."
        return 0
    fi

    git config --file "$git_cfg" user.name "$git_name"
    git config --file "$git_cfg" user.email "$git_email"
    git config --file "$git_cfg" init.defaultBranch main
    log_info "Git configuration written to: $git_cfg"
}

patch_ssh_config() {
    src_cfg="$SCRIPT_DIR/.ssh/config"
    dest_cfg="$HOME_DIR/.ssh/config"
    marker='# BEGIN dotfiles managed block'

    if [ ! -f "$src_cfg" ]; then
        log_info "No .ssh/config in dotfiles, skipping."
        return 0
    fi

    if [ -f "$dest_cfg" ] && grep -qF "$marker" "$dest_cfg"; then
        log_info ".ssh/config already contains the managed block, skipping."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: prepend dotfiles managed block to %s\n' "$dest_cfg"
        return 0
    fi

    run_cmd mkdir -p -m 700 "$HOME_DIR/.ssh"

    tmp_cfg=$(mktemp)
    trap 'rm -f "$tmp_cfg"' EXIT INT TERM HUP
    printf '%s\n' "$marker" > "$tmp_cfg"
    cat "$src_cfg"            >> "$tmp_cfg"
    printf '# END dotfiles managed block\n' >> "$tmp_cfg"
    if [ -f "$dest_cfg" ]; then
        printf '\n'           >> "$tmp_cfg"
        cat "$dest_cfg"       >> "$tmp_cfg"
    fi
    mv "$tmp_cfg" "$dest_cfg"
    chmod 600 "$dest_cfg"
    log_info "Patched: $dest_cfg"
}

patch_zshrc() {
    target_zshrc="$HOME_DIR/.zshrc"
    marker='# BEGIN dotfiles managed block'

    if [ ! -f "$target_zshrc" ]; then
        log_info ".zshrc not found, skipping."
        return 0
    fi

    if grep -qF "$marker" "$target_zshrc"; then
        log_info ".zshrc already contains the managed block, skipping."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: append dotfiles managed block to %s\n' "$target_zshrc"
        return 0
    fi

    cat >> "$target_zshrc" <<EOF

$marker
[ -f "\$HOME/.zshrc_personal" ] && source "\$HOME/.zshrc_personal"
# END dotfiles managed block
EOF
    log_info "Patched: $target_zshrc"
}

patch_bashrc() {
    target_bashrc="$HOME_DIR/.bashrc"
    marker='# BEGIN dotfiles managed block'

    if [ -f "$target_bashrc" ] && grep -qF "$marker" "$target_bashrc"; then
        log_info ".bashrc already contains the managed block, skipping."
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'DRY-RUN: append dotfiles managed block to %s\n' "$target_bashrc"
        return 0
    fi

    cat >> "$target_bashrc" <<EOF

$marker
if [ -f "\$HOME/.bash_personal" ]; then
    . "\$HOME/.bash_personal"
fi
# END dotfiles managed block
EOF
    log_info "Patched: $target_bashrc"
}

# bash files are nested under bash/bash/ and already carry dot prefixes
link_tree "$SCRIPT_DIR/bash/bash" "$HOME_DIR"

link_tree "$SCRIPT_DIR/nano"  "$HOME_DIR" 1
link_tree "$SCRIPT_DIR/tmux"  "$HOME_DIR" 1
link_tree "$SCRIPT_DIR/vim"   "$HOME_DIR" 1
link_tree "$SCRIPT_DIR/zsh"   "$HOME_DIR" 1

link_tree "$SCRIPT_DIR/git"    "$HOME_DIR"
link_tree "$SCRIPT_DIR/config" "$HOME_DIR/.config"

patch_ssh_config

patch_bashrc

configure_git

if [ "$DRY_RUN" -eq 1 ]; then
    log_info "Dry run completed. No files were changed."
else
    log_info "Installation completed."
fi
