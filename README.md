# Homelab Deploys

<p align="left">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/K3s-FFC61C.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="K3s"/>
  <img src="https://img.shields.io/badge/Ansible-black.svg?style=for-the-badge&logo=ansible&logoColor=white" alt="Ansible"/>
</p>

## Overview

The **Homelab Deploys** project is responsible for managing the software layer and workloads running on the personal Kubernetes (K3s) cluster. While the [`homelab-iac`](../homelab-iac/) repository handles the raw infrastructure (VMs and Proxmox), this project focuses on orchestrating networking services, security components, and applications.

It uses **Ansible** as the orchestration layer, driving Helm chart deployments and Kubernetes manifest applications through the `kubernetes.core` collection.

---

## What is it for?

This project automates the configuration of critical components for daily homelab operations:

- **Network LoadBalancer (MetalLB):** Provides real IP addresses from your local network to cluster services.
- **Ingress & Gateway (Envoy Gateway):** Implements the Kubernetes **Gateway API**, managing external traffic into your applications.
- **TLS Management (cert-manager):** Creates a dedicated internal Certificate Authority (CA). This allows all internal services to use HTTPS (`https://service.frank.lab.io`) with valid, trusted certificates.
- **Trust Automation:** Includes logic to automatically inject the Root CA certificate into your operating system (Linux) and browsers (Chrome/Firefox), eliminating "insecure connection" warnings.

---

## Core Components

| Component | Function |
| :--- | :--- |
| **MetalLB** | Layer 2 LoadBalancer for assigning local network IPs (e.g., `192.168.1.200`). |
| **Envoy Gateway** | Gateway API implementation for traffic routing and TLS termination. |
| **cert-manager** | Automatic TLS certificate issuance via Self-Signed ClusterIssuer (ECDSA-256). |
| **Podinfo** | Demo application used to validate the entire stack's functionality. |

---

## How to Use

### Prerequisites

- A functional Kubernetes cluster (installed via `homelab-iac`).
- `kubectl`, `helm`, `ansible`, `python3`/`pip3`, and `openssl` available in PATH.
- `pip3 install kubernetes watchdog` (required by `kubernetes.core` and the output plugin).

### First-time Setup

```bash
# Generate vault password (stored at ~/.config/homelab-iac/.vault_pass)
just secrets-keygen

# Install git hooks + Ansible Galaxy collections + check dependencies
just init
```

### Deployment

```bash
# Full deploy: cluster infra + apps + Root CA trust
just deploy

# Deploy only cluster infrastructure (MetalLB, Envoy Gateway, cert-manager, PKI)
just deploy-infra

# Deploy only applications
just deploy-apps

# Re-install Root CA into OS trust store and browsers (useful on a new machine)
just install-ca
```

### Secrets

```bash
just secrets-edit      # Decrypt → edit → re-encrypt vault.yml (recommended)
just secrets-view      # View decrypted vault.yml in terminal
just secrets-encrypt   # Manually encrypt vault.yml before committing
just secrets-decrypt   # Permanently decrypt vault.yml (use with caution)
```

---

## Project Structure

```
src/
├── main.yaml                  # Primary Ansible playbook (2 plays)
├── ansible.cfg                # Ansible config (beautiful_output callback)
├── hosts.yaml                 # Inventory: localhost (connection: local)
├── requirements.yml           # Galaxy collection: kubernetes.core
├── group_vars/
│   └── all/
│       ├── vars.yml           # Global variables (namespaces, versions, domain)
│       └── vault.yml          # Encrypted secrets (Ansible Vault)
├── callback_plugins/
│   └── beautiful_output.py    # Aesthetic output plugin
└── roles/
    ├── cluster-setup/         # Full cluster bootstrap (infra + networking + TLS + CA trust)
    └── podinfo/               # Demo application
```

---

## License

Distributed under the [CC BY-NC-SA 4.0](http://creativecommons.org/licenses/by-nc-sa/4.0/) license.
