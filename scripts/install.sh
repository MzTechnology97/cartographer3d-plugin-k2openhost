#!/bin/bash

set -euo pipefail

MODULE_NAME="cartographer.py"
PACKAGE_NAME="cartographer3d-plugin"
SCAFFOLDING="from cartographer.extra import *"
DEFAULT_KLIPPER_DIR="$HOME/klipper"
DEFAULT_KLIPPY_ENV="$HOME/klippy-env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

function display_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -k, --klipper       Set the Klipper/Kalico directory (default: $DEFAULT_KLIPPER_DIR)"
  echo "  -e, --klippy-env    Set the Klippy virtual environment directory (default: $DEFAULT_KLIPPY_ENV)"
  echo "  --uninstall         Uninstall the package and remove all scaffolding files"
  echo "  --help              Show this help message and exit"
  echo ""
  echo "K2-OpenHost installs this checkout in editable mode so git updates are used directly."
  exit 0
}

function parse_args() {
  uninstall=false
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -k | --klipper)
      klipper_dir="$2"
      shift 2
      ;;
    -e | --klippy-env)
      klippy_env="$2"
      shift 2
      ;;
    --uninstall)
      uninstall=true
      shift
      ;;
    --help)
      display_help
      ;;
    *)
      echo "Unknown option: $1"
      display_help
      ;;
    esac
  done
}

function check_directory_exists() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    echo "Error: Directory '$dir' does not exist."
    exit 1
  fi
}

function check_virtualenv_exists() {
  if [ ! -x "$klippy_env/bin/python" ] || [ ! -x "$klippy_env/bin/pip" ]; then
    echo "Error: '$klippy_env' is not a usable Python virtual environment."
    exit 1
  fi
}

function check_repo_checkout() {
  if [ ! -f "$REPO_ROOT/pyproject.toml" ] || [ ! -d "$REPO_ROOT/src/cartographer" ]; then
    echo "Error: unable to locate the Cartographer source tree at '$REPO_ROOT'."
    exit 1
  fi
}

function ensure_numpy() {
  echo "Checking numpy installation in '$klippy_env'..."

  "$klippy_env/bin/python" -c "
import sys
try:
    import numpy
    version = tuple(map(int, numpy.__version__.split('.')[:2]))
    if version >= (1, 16):
        print(f'✓ numpy {numpy.__version__} already installed and >= 1.16')
        sys.exit(0)
    print(f'numpy {numpy.__version__} found but < 1.16, upgrading...')
    sys.exit(1)
except ImportError:
    print('numpy not found, installing numpy~=1.16...')
    sys.exit(1)
" || "$klippy_env/bin/pip" install "numpy~=1.16"
}

function install_dependencies() {
  ensure_numpy
  echo "Installing K2-OpenHost Cartographer from '$REPO_ROOT' into '$klippy_env' (editable)..."
  "$klippy_env/bin/pip" install --upgrade -e "$REPO_ROOT"
  echo "'$PACKAGE_NAME' is installed from the local K2-OpenHost checkout."
}

function uninstall_dependencies() {
  echo "Uninstalling '$PACKAGE_NAME' from '$klippy_env'..."
  "$klippy_env/bin/pip" uninstall -y "$PACKAGE_NAME"
  echo "'$PACKAGE_NAME' has been uninstalled from '$klippy_env'."
}

function create_scaffolding() {
  if [ -d "$klipper_dir/klippy/plugins" ]; then
    scaffolding_dir="$klipper_dir/klippy/plugins"
    use_git_exclude=false
  else
    scaffolding_dir="$klipper_dir/klippy/extras"
    use_git_exclude=true
  fi

  scaffolding_path="$scaffolding_dir/$MODULE_NAME"
  scaffolding_rel_path="${scaffolding_dir#"$klipper_dir"/}/$MODULE_NAME"

  check_directory_exists "$scaffolding_dir"

  if [ -L "$scaffolding_path" ]; then
    local original_target
    original_target=$(readlink "$scaffolding_path")
    echo "Warning: '$scaffolding_path' is a symlink and will be replaced."
    echo "Previous target: $original_target"
    rm "$scaffolding_path"
  fi

  printf '%s\n' "$SCAFFOLDING" >"$scaffolding_path"
  echo "Created '$scaffolding_path'."

  if [ "$use_git_exclude" = true ]; then
    local exclude_file="$klipper_dir/.git/info/exclude"
    if [ -d "$klipper_dir/.git" ]; then
      mkdir -p "$(dirname "$exclude_file")"
      touch "$exclude_file"
      if ! grep -qF "$scaffolding_rel_path" "$exclude_file" >/dev/null 2>&1; then
        echo "$scaffolding_rel_path" >>"$exclude_file"
        echo "Added '$scaffolding_rel_path' to git exclude."
      fi
    fi
  fi
}

function remove_plugin_files() {
  echo "Cleaning up legacy/scaffolding files..."

  local files=("idm.py" "scanner.py" "cartographer.py")
  local paths=(
    "$klipper_dir/klippy/extras"
    "$klipper_dir/klippy/plugins"
  )

  for dir in "${paths[@]}"; do
    if [ ! -d "$dir" ]; then
      continue
    fi

    for file in "${files[@]}"; do
      local full_path="$dir/$file"
      local rel_path="${dir#"$klipper_dir"/}/$file"

      if [ -f "$full_path" ] || [ -L "$full_path" ]; then
        if [ -L "$full_path" ]; then
          local original_target
          original_target=$(readlink "$full_path" 2>/dev/null || echo "unknown")
          echo "Removing symlink '$full_path' (target: $original_target)"
        else
          echo "Removing file '$full_path'"
        fi
        rm "$full_path"

        local exclude_file="$klipper_dir/.git/info/exclude"
        if [ -f "$exclude_file" ]; then
          sed -i "\|^$rel_path\$|d" "$exclude_file" 2>/dev/null || true
        fi
      fi
    done
  done
}

function main() {
  klipper_dir="$DEFAULT_KLIPPER_DIR"
  klippy_env="$DEFAULT_KLIPPY_ENV"

  parse_args "$@"

  check_directory_exists "$klipper_dir"
  check_virtualenv_exists
  check_repo_checkout

  remove_plugin_files

  if [ "$uninstall" = true ]; then
    uninstall_dependencies
  else
    install_dependencies
    create_scaffolding
  fi
}

main "$@"
