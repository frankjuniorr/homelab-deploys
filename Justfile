set shell := ["bash", "-c"]

# Helper para rodar ansible com inventário local
ansible_cmd := "ansible-playbook -i " + quote(invocation_directory() + "/src/hosts.yaml")

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
    ./scripts/check_dependencies.sh
    ansible-galaxy install -r src/requirements.yml

############################################################################
# DEPLOY
############################################################################
# Deploy completo: cluster-setup (namespaces + CRDs + Helm + configs + CA trust) + apps
deploy: init
    cd src && {{ansible_cmd}} main.yaml --tags "setup"

# Deploy apenas a infraestrutura do cluster (sem apps)
deploy-infra:
    cd src && {{ansible_cmd}} main.yaml --tags "infra"

# Deploy apenas as aplicações (requer cluster já configurado)
deploy-apps:
    cd src && {{ansible_cmd}} main.yaml --tags "apps"

# Instala apenas o certificado Root CA no trust store local e navegadores
# Útil após rotação de CA ou em uma nova máquina com o cluster já rodando
install-ca:
    cd src && {{ansible_cmd}} main.yaml --tags "ca-trust"

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
