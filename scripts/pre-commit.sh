#!/usr/bin/env bash

# Função: ensure_plugin_on
# Objetivo: Garante que o plugin estético do Ansible esteja ativado ao commitar.
ensure_plugin_on() {
  if command -v just >/dev/null 2>&1; then
    just plugin on
  else
    sed -i '/^# *stdout_callback = beautiful_output/s/^# *//' src/ansible.cfg
    echo "Plugin 'beautiful_output' ATIVADO via fallback (sed)."
  fi
}

# Função: add_git_files
# Objetivo: Re-adiciona arquivos modificados pelo hook para garantir que as alterações vão no commit.
add_git_files() {
  FILES=$(git diff --cached --name-only --diff-filter=ACMR)
  if [ -n "$FILES" ]; then
    git add $FILES
  fi
}

# Função: ensure_scripts_executable
# Objetivo: Garante que todos os scripts na pasta scripts/ tenham permissão de execução.
ensure_scripts_executable() {
  chmod +x scripts/*.sh
  chmod +x .git/hooks/pre-commit
}

# Execução das verificações de forma sequencial
ensure_scripts_executable
ensure_plugin_on
add_git_files

exit 0
