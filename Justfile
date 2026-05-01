set shell := ["bash", "-c"]

# Variáveis
export VAULT_PASS_FILE := home_dir() + "/.config/homelab-iac/.vault_pass"

# Helper para rodar ansible com inventário local
ansible_cmd := "ansible-playbook -i " + quote(invocation_directory() + "/src/hosts.yaml") + " --vault-password-file " + VAULT_PASS_FILE

############################################################################
# INIT
############################################################################
# Instala git hooks e verifica dependências
install-hooks:
    @echo "Installing git pre-commit hook..."
    @cp -f scripts/pre-commit.sh .git/hooks/pre-commit
    @chmod +x .git/hooks/pre-commit
    @echo "Hook installed successfully."

# Configuração inicial do ambiente:
# 1. Verifica dependências (kubectl, helm, kustomize, ansible, python libs)
# 2. Instala coleções Ansible do Galaxy (kubernetes.core)
init: install-hooks
    @./scripts/check_dependencies.sh
    @ansible-galaxy collection install -r src/requirements.yml

############################################################################
# DEPLOY
############################################################################
# Deploy completo por padrão; passa uma tag para rodar apenas aquele subset
# Exemplos: just deploy | just deploy pgadmin | just deploy velero | just deploy infra
deploy tag="setup": init
    @cd src && {{ansible_cmd}} main.yaml --tags "{{tag}}"

# Deploy apenas a infraestrutura do cluster (sem apps)
deploy-infra:
    @cd src && {{ansible_cmd}} main.yaml --tags "infra"

# Deploy apenas as aplicações (requer cluster já configurado)
deploy-apps:
    @cd src && {{ansible_cmd}} main.yaml --tags "apps"

# Instala apenas o certificado Root CA no trust store local e navegadores
# Útil após rotação de CA ou em uma nova máquina com o cluster já rodando
install-ca:
    @cd src && {{ansible_cmd}} main.yaml --tags "ca-trust"

# Remove todos os namespaces criados pelo homelab-deploys, zerando o cluster
# ATENÇÃO: irreversível — requer `just deploy` para restaurar
destroy:
    @cd src && {{ansible_cmd}} destroy.yaml

############################################################################
# SECRETS (Ansible-Vault)
############################################################################
# Cria um novo arquivo de senha para o vault se não existir em ~/.config/homelab-iac/.vault_pass
secrets-keygen:
    @test ! -d ~/.config/homelab-iac && mkdir -p ~/.config/homelab-iac
    @test ! -f {{VAULT_PASS_FILE}} && openssl rand -base64 32 > {{VAULT_PASS_FILE}} && chmod 600 {{VAULT_PASS_FILE}} || echo "Vault password file already exists"

# Criptografa o arquivo vault.yml (Garante segurança no Git)
secrets-encrypt:
    @if ! grep -q "\$ANSIBLE_VAULT" src/group_vars/all/vault.yml; then \
        ansible-vault encrypt src/group_vars/all/vault.yml --vault-password-file {{VAULT_PASS_FILE}} && echo "src/group_vars/all/vault.yml encrypted"; \
    else \
        echo "src/group_vars/all/vault.yml already encrypted"; \
    fi

# Abre o vault.yml criptografado diretamente no editor padrão
secrets-edit:
    @ansible-vault edit src/group_vars/all/vault.yml --vault-password-file {{VAULT_PASS_FILE}}

# Descriptografa o vault.yml permanentemente (use com cautela)
secrets-decrypt:
    @if grep -q "\$ANSIBLE_VAULT" src/group_vars/all/vault.yml; then \
        ansible-vault decrypt src/group_vars/all/vault.yml --vault-password-file {{VAULT_PASS_FILE}} && echo "src/group_vars/all/vault.yml decrypted"; \
    else \
        echo "src/group_vars/all/vault.yml is already decrypted"; \
    fi

# Apenas visualiza os segredos descriptografados no terminal
secrets-view:
    @ansible-vault view src/group_vars/all/vault.yml --vault-password-file {{VAULT_PASS_FILE}}

############################################################################
# VELERO BACKUP / RESTORE
############################################################################
# Backup manual: dispara Velero (objetos K8s + PVC data) imediatamente
# Uso: just backup            (nome Velero automático: manual-backup-YYYYMMDD-HHMMSS)
#      just backup NOME       (nome Velero customizado)
# Nota: backup do PostgreSQL LXC é gerenciado pelo homelab-iac (pg_dump → Garage S3, cron 01:45)
backup name="":
    @if [ -n "{{name}}" ]; then \
        ./scripts/velero-backup.sh "{{name}}"; \
    else \
        ./scripts/velero-backup.sh; \
    fi

# Restore manual: recupera dados do último backup completo no S3
# Uso: just restore            (usa o backup mais recente)
#      just restore NOME       (usa um backup específico pelo nome)
# Pré-requisito: criar o bucket homelab-velero no Garage via aws-cli antes do primeiro deploy
restore backup="":
    @if [ -n "{{backup}}" ]; then \
        ./scripts/velero-restore.sh "{{backup}}"; \
    else \
        ./scripts/velero-restore.sh; \
    fi

# Recria o token Gotify usado pelo checker de backup do Velero
# Use quando o Gotify for resetado (PVC deletado) e o token anterior ficou inválido:
#   kubectl delete secret velero-gotify-token -n velero --ignore-not-found
#   just deploy gotify
reset-gotify-token:
    @kubectl delete secret velero-gotify-token -n velero --ignore-not-found
    @just deploy gotify

############################################################################
# PR REVIEW
############################################################################
# Lista PRs abertos e permite aprovar/mergear interativamente (requer gum)
pr-review:
    @./scripts/pr-review.sh

# Lista PRs abertos em formato legível (não-interativo, para scripts/Claude)
pr-list:
    @./scripts/pr-review.sh --list

############################################################################
# UTILS
############################################################################
# Liga/Desliga o plugin de saída estética (beautiful_output) para visualização ou debug
plugin state:
    @if [ "{{state}}" == "on" ]; then \
        sed -i '/^# *stdout_callback = beautiful_output/s/^# *//' src/ansible.cfg; \
        echo "Plugin 'beautiful_output' ATIVADO."; \
    elif [ "{{state}}" == "off" ]; then \
        sed -i '/^stdout_callback = beautiful_output/s/^/# /' src/ansible.cfg; \
        echo "Plugin 'beautiful_output' DESATIVADO."; \
    else \
        echo "Use: just plugin on ou just plugin off"; \
    fi
