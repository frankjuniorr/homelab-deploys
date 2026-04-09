#!/bin/bash

function command_exists() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

function python_lib_exists() {
  local lib="$1"
  pip3 freeze 2>/dev/null | grep -i "^${lib}==" >/dev/null 2>&1
}

function install_python_lib() {
  local lib="$1"
  echo "Attempting to install python lib: $lib"

  os_name=$(grep "^NAME=" /etc/os-release 2>/dev/null | cut -d '=' -f2 | sed 's/"//g')

  case $os_name in
  "Ubuntu") sudo apt install python3-${lib} -y && return 0 ;;
  "Arch Linux") sudo pacman -S --needed --noconfirm python-${lib} && return 0 ;;
  esac

  echo "OS package failed, falling back to pip3..."
  pip3 install "$lib"
}

#########################################################################
# MAIN
#########################################################################

# CLI tools required to run the playbooks
os_commands=(
  "ansible"    # Ansible
  "python3"    # Python
  "pip3"       # pip3
  "kubectl"    # Kubernetes CLI
  "helm"       # Helm (used by kubernetes.core.helm module)
  "openssl"    # Certificate operations (used by cert renewal guard in cluster-setup)
)

# Python libs required by Ansible collections
python_libs=(
  "watchdog"    # Used by beautiful_output.py callback plugin
  "kubernetes"  # Used by kubernetes.core collection
)

for cmd in "${os_commands[@]}"; do
  if ! command_exists "$cmd"; then
    echo "❌ Command '$cmd' is NOT installed."
    exit 1
  fi
done

for lib in "${python_libs[@]}"; do
  if ! python_lib_exists "$lib"; then
    echo "⚠️  Python lib '$lib' is NOT installed. Attempting to install..."
    install_python_lib "$lib"
  fi
done

echo "✅ All dependencies are satisfied."
