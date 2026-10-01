#!/bin/bash

set -euo pipefail

MODULE_NAME="cartographer.py"
PACKAGE_NAME="cartographer3d-plugin"
SCAFFOLDING="from cartographer.extra import *"
DEFAULT_KLIPPER_DIR="$HOME/klipper"
DEFAULT_KLIPPY_ENV="$HOME/klippy-env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQUIREMENTS_FILE="$REPO_ROOT/requirements.txt"

function display_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -k, --klipper DIR       Klipper/Kalico directory (default: $DEFAULT_KLIPPER_DIR)
  -e, --klippy-env DIR    Klippy virtual environment (default: $DEFAULT_KLIPPY_ENV)
  --uninstall             Uninstall the Python package and remove scaffolding
  --help                  Show this help message

K2-OpenHost installs this checkout in editable mode.  Normal Git/Moonraker
updates therefore update the code used by Kalico without reinstalling the
package.  Runtime dependencies are declared in requirements.txt so Moonraker
can maintain them when configured with `virtualenv` + `requirements`.
EOF
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
      echo "Unknown option: $1" >&2
      display_help
      ;;
    esac
  done
}

function check_directory_exists() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "Error: Directory '$dir' does not exist." >&2
    exit 1
  fi
}

function check_virtualenv_exists() {
  if [[ ! -x "$klippy_env/bin/python" ]] || [[ ! -x "$klippy_env/bin/pip" ]]; then
    echo "Error: '$klippy_env' is not a usable Python virtual environment." >&2
    exit 1
  fi
}

function check_repo_checkout() {
  if [[ ! -f "$REPO_ROOT/pyproject.toml" ]] || [[ ! -d "$REPO_ROOT/src/cartographer" ]]; then
    echo "Error: unable to locate the Cartographer source tree at '$REPO_ROOT'." >&2
    exit 1
  fi
  if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    echo "Error: runtime requirements file '$REQUIREMENTS_FILE' is missing." >&2
    exit 1
  fi
}

function install_dependencies() {
  echo "Installing runtime requirements into '$klippy_env'..."
  "$klippy_env/bin/pip" install --upgrade -r "$REQUIREMENTS_FILE"

  echo "Installing K2-OpenHost Cartographer from '$REPO_ROOT' (editable)..."
  # Dependencies are maintained explicitly through requirements.txt.  Keeping
  # the editable package separate is important for Moonraker: a Git pull then
  # changes the source imported by Kalico immediately.
  "$klippy_env/bin/pip" install --upgrade --no-deps -e "$REPO_ROOT"
  echo "'$PACKAGE_NAME' is installed from the local K2-OpenHost checkout."
}

function uninstall_dependencies() {
  echo "Uninstalling '$PACKAGE_NAME' from '$klippy_env'..."
  "$klippy_env/bin/pip" uninstall -y "$PACKAGE_NAME"
  echo "'$PACKAGE_NAME' has been uninstalled from '$klippy_env'."
}

function remove_plugin_files() {
  echo "Cleaning legacy/scaffolding plugin loaders..."

  local files=("idm.py" "scanner.py" "cartographer.py")
  local paths=(
    "$klipper_dir/klippy/extras"
    "$klipper_dir/klippy/plugins"
  )

  for dir in "${paths[@]}"; do
    [[ -d "$dir" ]] || continue

    for file in "${files[@]}"; do
      local full_path="$dir/$file"
      local rel_path="${dir#"$klipper_dir"/}/$file"

      if [[ -f "$full_path" ]] || [[ -L "$full_path" ]]; then
        if [[ -L "$full_path" ]]; then
          echo "Removing symlink '$full_path' -> $(readlink "$full_path" 2>/dev/null || echo unknown)"
        else
          echo "Removing file '$full_path'"
        fi
        rm -f "$full_path"

        local exclude_file="$klipper_dir/.git/info/exclude"
        if [[ -f "$exclude_file" ]]; then
          sed -i "\|^$rel_path\$|d" "$exclude_file" 2>/dev/null || true
        fi
      fi
    done
  done
}

function create_scaffolding() {
  local scaffolding_dir
  local use_git_exclude

  if [[ -d "$klipper_dir/klippy/plugins" ]]; then
    scaffolding_dir="$klipper_dir/klippy/plugins"
    use_git_exclude=false
  else
    scaffolding_dir="$klipper_dir/klippy/extras"
    use_git_exclude=true
  fi

  check_directory_exists "$scaffolding_dir"

  local scaffolding_path="$scaffolding_dir/$MODULE_NAME"
  local scaffolding_rel_path="${scaffolding_dir#"$klipper_dir"/}/$MODULE_NAME"

  printf '%s\n' "$SCAFFOLDING" >"$scaffolding_path"
  echo "Created '$scaffolding_path'."

  if [[ "$use_git_exclude" == true ]] && [[ -d "$klipper_dir/.git" ]]; then
    local exclude_file="$klipper_dir/.git/info/exclude"
    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    if ! grep -qF "$scaffolding_rel_path" "$exclude_file" >/dev/null 2>&1; then
      echo "$scaffolding_rel_path" >>"$exclude_file"
      echo "Added '$scaffolding_rel_path' to the local Kalico Git exclude file."
    fi
  fi
}

function print_next_steps() {
  cat <<EOF

K2-OpenHost Cartographer installation complete.

Recommended transport:
  Connect Cartographer directly to the external Kalico host and use its
  /dev/serial/by-id/... path.  Keep ttyUSB0/1/2 dedicated to K2 Main MCU,
  Nozzle MCU and RS485/CFS respectively.

Moonraker/Mainsail updates:
  See README.md and docs/UPDATE_MANAGER.md.  Do not configure `install_script`
  as a post-update hook; Moonraker does not execute it that way.
EOF
}

function main() {
  klipper_dir="$DEFAULT_KLIPPER_DIR"
  klippy_env="$DEFAULT_KLIPPY_ENV"

  parse_args "$@"

  check_directory_exists "$klipper_dir"
  check_virtualenv_exists
  check_repo_checkout

  remove_plugin_files

  if [[ "$uninstall" == true ]]; then
    uninstall_dependencies
  else
    install_dependencies
    create_scaffolding
    print_next_steps
  fi
}

main "$@"
