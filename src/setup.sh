#!/bin/bash
set -e

# Verificações básicas
if ! command -v helm &>/dev/null; then
  echo "❌ Erro: 'helm' não está instalado."
  exit 1
fi

if ! command -v kustomize &>/dev/null; then
  echo "❌ Erro: 'kustomize' não está instalado."
  exit 1
fi

echo "📂 Criando Namespaces necessários..."
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace envoy-gateway-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

echo "🚀 Passo 1: Instalando Standard Gateway API CRDs..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml

echo "🏗️ Passo 2: Instalando Infraestrutura (Helm Charts via Kustomize)..."
kustomize build --enable-helm ./infra | kubectl apply -f - --server-side --force-conflicts
[ -d "./infra/charts" ] && rm -rf ./infra/charts # Limpa os charts baixados caso existam

echo "⏳ Aguardando CRDs ficarem prontas..."
sleep 15
kubectl wait --for=condition=established crd/ipaddresspools.metallb.io --timeout=90s
kubectl wait --for=condition=established crd/gateways.gateway.networking.k8s.io --timeout=90s
kubectl wait --for=condition=established crd/certificates.cert-manager.io --timeout=90s

echo "⚙️ Passo 3: Aplicando Configurações (Base Configs)..."
kubectl apply -k ./infra/base

# --- NOVA LÓGICA: FORÇAR RENOVAÇÃO DO CERTIFICADO DO SITE ---
# Se o certificado do site não foi emitido pela nossa nova CA, deletamos para forçar a renovação
if kubectl get secret homelab-wildcard-tls &>/dev/null; then
  ISSUER_CN=$(kubectl get secret homelab-wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer | grep -o "Homelab Internal Root CA" || echo "old")
  if [ "$ISSUER_CN" != "Homelab Internal Root CA" ]; then
      echo "♻️ Certificado antigo detectado. Forçando renovação pelo novo Root CA..."
      kubectl delete secret homelab-wildcard-tls
  fi
fi
# -----------------------------------------------------------

echo "📦 Passo 4: Deploy das Aplicações..."
kubectl apply -k ./apps/podinfo

echo "🔐 Passo 5: Configurando Confiança no Certificado Root CA..."

# Aguarda o Secret da CA ser gerado pelo cert-manager
echo "Aguardando geração do Secret homelab-ca-tls..."
until kubectl get secret homelab-ca-tls -n cert-manager &>/dev/null; do sleep 2; done

# Extrai o certificado
kubectl get secret homelab-ca-tls -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d >homelab-root-ca.crt

# Identifica a Distro via /etc/os-release e Instala
if [ -f /etc/os-release ]; then
  . /etc/os-release
  case "$ID" in
  arch)
    echo "Detected: Arch Linux"
    sudo cp homelab-root-ca.crt /etc/ca-certificates/trust-source/anchors/homelab-root-ca.crt
    sudo update-ca-trust
    echo "✅ Certificado instalado no Arch Linux via update-ca-trust"
    ;;
  ubuntu | debian)
    echo "Detected: Ubuntu/Debian ($ID)"
    sudo cp homelab-root-ca.crt /usr/local/share/ca-certificates/homelab-root-ca.crt
    sudo update-ca-certificates
    echo "✅ Certificado instalado no Ubuntu/Debian via update-ca-certificates"
    ;;
  *)
    echo "⚠️ Sistema operacional ($ID) não identificado para instalação automática do certificado."
    echo "O arquivo 'homelab-root-ca.crt' foi gerado. Instale-o manualmente no seu sistema."
    ;;
  esac

  # --- INJEÇÃO NO BANCO NSS (CHROME/FIREFOX NO LINUX) ---
  if command -v certutil &>/dev/null; then
    echo "🔍 Detectado 'certutil'. Injetando certificado nas bases NSS do Chrome/Firefox..."
    for db in $(find $HOME -name "cert9.db" 2>/dev/null); do
        db_dir=$(dirname "$db")
        certutil -A -n "Homelab Root CA" -t "TC,," -i homelab-root-ca.crt -d "sql:$db_dir"
        echo "✅ Injetado em: $db_dir"
    done
  else
    echo "ℹ️ Dica: Instale o pacote 'nss' (Arch) ou 'libnss3-tools' (Ubuntu) para que o Chrome confie automaticamente sem precisar de configurações manuais."
  fi
  # -----------------------------------------------------

else
  echo "⚠️ /etc/os-release não encontrado. O certificado 'homelab-root-ca.crt' foi gerado, mas não pôde ser instalado automaticamente."
fi

echo "✅ Verificando o IP atribuído ao Gateway..."
echo "Aguardando o Envoy provisionar o IP do LoadBalancer (MetalLB)..."
sleep 20
kubectl get gateway my-gateway
