#!/usr/bin/env bash

# Função: check_encrypt_vault_file
# Objetivo: Verificar se o vault.yml contém os metadados do Ansible-Vault antes de permitir o commit.
#           Se não estiver criptografado, criptografa automaticamente e re-adiciona ao stage.
check_encrypt_vault_file() {
  VAULT_FILE="src/group_vars/all/vault.yml"

  if [ -f "$VAULT_FILE" ]; then
    # IMPORTANTE: Usamos 'git show :path' para olhar o conteúdo que está no STAGE
    if git show :"$VAULT_FILE" | grep -q "\$ANSIBLE_VAULT"; then
      return 0 # Sucesso: o arquivo está encriptado, continua para a próxima função
    else
      echo "⚠️  $VAULT_FILE is not encrypted. Encrypting automatically..."
      just secrets-encrypt
      git add "$VAULT_FILE"
      echo "✅ $VAULT_FILE encrypted and re-staged."
    fi
  fi
}

# Função: ensure_plugin_on
# Objetivo: Garante que o plugin estético do Ansible esteja ativado ao commitar.
ensure_plugin_on() {
  if command -v just >/dev/null 2>&1; then
    just plugin on
  else
    # Fallback caso o just não esteja no PATH (ex: ambientes de CI ou hooks restritos)
    sed -i '/^# *stdout_callback = beautiful_output/s/^# *//' src/ansible.cfg
    echo "Plugin 'beautiful_output' ATIVADO via fallback (sed)."
  fi
}

# Função: add_git_files
# Objetivo: Garante que os arquivos modificados e adicionados ao stage sejam processados corretamente.
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
  # Garante que o próprio hook tenha permissão (caso seja atualizado)
  chmod +x .git/hooks/pre-commit
}

# Execução das verificações de forma sequencial
ensure_scripts_executable
check_encrypt_vault_file
ensure_plugin_on
add_git_files

exit 0
