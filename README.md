# Homelab Deploys

<p align="left">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/K3s-FFC61C.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="K3s"/>
  <img src="https://img.shields.io/badge/Ansible-black.svg?style=for-the-badge&logo=ansible&logoColor=white" alt="Ansible"/>
  <img src="https://img.shields.io/badge/Velero-blue.svg?style=for-the-badge" alt="Velero"/>
</p>

The **software/workload layer** of a personal K3s homelab. While [`homelab-iac`](../homelab-iac/) provisions the raw infrastructure (Proxmox VMs, K3s cluster), this repo configures everything that runs on top of it: networking, TLS, observability, storage, backup/DR, and applications — all driven by Ansible.

---

## Core Components

| Component | Namespace | Description |
| :--- | :--- | :--- |
| **MetalLB** | `metallb-system` | Layer 2 LoadBalancer — assigns real LAN IPs (`192.168.1.200–205`) to services |
| **Envoy Gateway** | `envoy-gateway-system` | Gateway API implementation — routes external traffic and terminates TLS |
| **cert-manager** | `cert-manager` | Internal CA with auto-issued wildcard cert for `*.frank.lab.io` (ECDSA-256) |
| **Longhorn** | `longhorn-system` | Distributed block storage — default StorageClass for all PVCs |
| **Velero** | `velero` | Cluster backup/DR — automatic scheduled backups to Garage S3, auto-restore on first deploy |
| **CloudNativePG** | `cnpg-system` | PostgreSQL operator |
| **PostgreSQL** | `postgres` | Managed PostgreSQL cluster via CloudNativePG |
| **Prometheus** | `prometheus` | kube-prometheus-stack — metrics, alerting, kube-state-metrics, node-exporter |
| **Grafana** | `grafana` | Standalone dashboards with Prometheus + Loki datasources |
| **Loki + Promtail** | `loki` | Log aggregation and pod log collection |
| **node_exporter** | host | Systemd service on the Proxmox host; exposes host + per-VM/LXC metrics on `:9100` |
| **Podinfo** | `podinfo` | Demo app — validates the full stack end-to-end |

---

## How to Use

### Prerequisites

- A running K3s cluster provisioned via `homelab-iac`
- `kubectl`, `helm`, `ansible`, `python3`/`pip3`, `openssl`, `aws` CLI in PATH
- Python dependencies: `pip3 install kubernetes watchdog`
- `~/.aws/credentials` configured with Garage S3 credentials (profile: `default`)

### First-time Setup

```bash
just secrets-keygen   # Generate vault password at ~/.config/homelab-iac/.vault_pass
just init             # Install hooks + Ansible Galaxy collections + check dependencies
```

> [!IMPORTANT]
> The `homelab-velero` bucket must exist in Garage S3 before the first deploy.

### Deployment

```bash
just deploy           # Full deploy: infra + apps + Root CA trust + Proxmox node_exporter
just deploy-infra     # Cluster infra only (MetalLB, Envoy Gateway, cert-manager, PKI)
just deploy-apps      # Applications only (includes Velero auto-restore on first deploy)
just install-ca       # Re-install Root CA into OS trust store and browsers
just destroy          # Wipe all cluster namespaces + remove node_exporter from Proxmox host
```

> [!TIP]
> Run `just plugin off` before deploying when you need to debug Ansible task output — the default pretty-printer can swallow error details.

### Backup and Restore

Velero backs up all cluster namespaces — Kubernetes resources and PVC data (via Kopia) — to Garage S3 on an automatic schedule. Backups are retained for 30 days.

On the **first `just deploy`** after a full cluster destroy, Velero automatically detects existing backups and restores the cluster state before the rest of the apps deploy.

```bash
just restore            # Restore from the most recent completed backup
just restore NOME       # Restore from a specific backup by name
```

```bash
# Inspect backups and restores
kubectl get backup.velero.io -n velero
kubectl get restore.velero.io -n velero
```

### Secrets

```bash
just secrets-edit     # Decrypt → edit → re-encrypt vault.yml (recommended)
just secrets-view     # View decrypted vault.yml in terminal
just secrets-encrypt  # Manually encrypt vault.yml before committing
just secrets-decrypt  # Permanently decrypt vault.yml (use with caution)
```

---

## Project Structure

```
src/
├── main.yaml                        # Primary Ansible playbook
├── ansible.cfg                      # Ansible config (beautiful_output callback)
├── hosts.yaml                       # Inventory: localhost + proxmox_node
├── requirements.yml                 # Galaxy collection: kubernetes.core
├── group_vars/all/
│   ├── vars.yml                     # Namespaces, versions, domains, resource limits
│   └── vault.yml                    # Encrypted secrets (Ansible Vault)
├── callback_plugins/
│   └── beautiful_output.py          # Aesthetic output plugin
└── roles/
    ├── cluster-setup/               # Bootstrap: Gateway API CRDs → Helm charts → PKI → CA trust
    ├── longhorn/                    # Distributed block storage (Helm)
    ├── velero/                      # Backup/DR: Kopia + Garage S3, auto-restore on first deploy
    ├── postgres/                    # CloudNativePG operator + PostgreSQL cluster
    ├── podinfo/                     # Demo app (Deployment + Service + HTTPRoute)
    ├── monitoring/                  # Prometheus + Loki + Promtail (Helm)
    ├── grafana/                     # Grafana Helm install + all dashboard ConfigMaps
    │   └── files/dashboards/        # Dashboard definitions as plain .json files
    │       ├── cluster-logs.json    # Cluster-wide log monitoring (Loki)
    │       ├── pod-logs.json        # Per-pod log explorer (Loki)
    │       └── proxmox-node.json    # Proxmox host + VM/LXC metrics (Prometheus)
    └── proxmox-node/                # node_exporter + VM/LXC metrics script on Proxmox host
```

### Tags for Granular Runs

```bash
ansible-playbook src/main.yaml --tags <tag>
```

| Tag | Scope |
| :--- | :--- |
| `setup` | Everything (full deploy) |
| `infra` | `cluster-setup` role only |
| `apps` | All application roles |
| `longhorn` | Longhorn role only |
| `velero` | Velero role only (includes auto-restore check) |
| `postgres` | CloudNativePG operator + PostgreSQL cluster |
| `monitoring` | Prometheus + Loki + Promtail only |
| `grafana` | Grafana install + all dashboards only |
| `podinfo` | podinfo role only |
| `proxmox-node` | node_exporter on Proxmox host only |
| `ca-trust` | Root CA OS/browser trust tasks only |

---

## License

Distributed under the [CC BY-NC-SA 4.0](http://creativecommons.org/licenses/by-nc-sa/4.0/) license.
