# Run from any directory using: just --justfile ~/src/dotfiles/justfile doctor
default:
    @just --list

check:
    scripts/check

# Uses installed configuration and language servers; portable CI is separate.
editor-check:
    python3.14 scripts/editor_check.py

doctor:
    scripts/dotfiles doctor --all

preview:
    ./install.sh --all --deps --dry-run

install:
    ./install.sh --all --deps

# Deliberate maintenance; installs remain --no-upgrade by default.
outdated:
    brew outdated

brew-check:
    brew bundle check --no-upgrade --file=Brewfile
