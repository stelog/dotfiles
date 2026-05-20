# dotfiles

Repository to manage my dotfiles.

## Structure

| Folder    | Target in `$HOME` (default) |
|-----------|------------------------------|
| `bash/`   | `~/`                         |
| `nano/`   | `~/`                         |
| `tmux/`   | `~/`                         |
| `vim/`    | `~/`                         |
| `zsh/`    | `~/`                         |
| `config/` | `~/.config/`                 |

The installer also patches existing config files:

- **`~/.bashrc`** — appends a block that sources `~/.bash_personal`
- **`~/.zshrc`** — appends a block that sources `~/.zshrc_personal` (only if the file exists)
- **`~/.ssh/config`** — prepends the dotfiles SSH hardening block (only if not already present)

## Installation

```sh
./install.sh
```

If a target symlink already exists it is skipped with a warning. Use `--force`
to overwrite — a timestamped `.bak` backup is created before any file is
replaced:

```sh
./install.sh --force
```

### Options

| Flag | Description |
|------|-------------|
| `-n`, `--dry-run`, `--try-run` | Print actions without changing anything |
| `-f`, `--force` | Overwrite existing files (backs them up first) |
| `--home DIR`, `--target DIR` | Install into `DIR` instead of `$HOME` |
| `-h`, `--help` | Show usage |

### Testing with a different target directory

```sh
./install.sh --dry-run --home /tmp/dotfiles-home
```

The target directory is created automatically if it does not exist.
