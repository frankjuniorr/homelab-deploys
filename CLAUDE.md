# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repo is the **software/workload layer** of a personal K3s (lightweight Kubernetes) cluster. It is a direct continuation of [`homelab-iac`](../homelab-iac/), which provisions the raw Proxmox infrastructure (VMs, LXC containers, K3s cluster). Everything here assumes that cluster is already running.

**Dependency chain:**
```
homelab-iac  →  homelab-deploys
(Proxmox VMs + K3s cluster)   (networking, TLS, workloads on K8s)
```

All entry points go through `just` (the Justfile task runner). The legacy `setup.sh` is kept for reference but superseded by Ansible.

## Common Commands

```bash
# First-time setup
just init              # Install hooks + Ansible Galaxy collections + check dependencies

# Deployment
just deploy            # Full deploy (namespaces + CRDs + infra + apps + Root CA trust)
just deploy-infra      # Only infra layer (namespaces, CRDs, Helm charts, base configs)
just deploy-apps       # Only applications (podinfo and any new apps)
just install-ca        # Only install Root CA into OS trust store and browser NSS databases

# Debugging
just plugin off        # Disable aesthetic plugin to see raw Ansible output
just plugin on         # Re-enable aesthetic plugin
```

**Prerequisites:** `kubectl`, `helm`, `ansible`, `python3`/`pip3`, `openssl` must be available in PATH.

## Architecture

```
Justfile → Ansible playbooks (src/) → kubernetes.core modules → K3s cluster
```

- **`src/main.yaml`** — Primary deployment playbook; uses tags to target subsets
- **`src/hosts.yaml`** — Ansible inventory (`localhost` with `connection: local`)
- **`src/roles/`** — Two self-contained roles; each owns its Kubernetes manifests in `files/`
- **`src/group_vars/all.yml`** — Global variables (namespaces, versions, domain, cert names)

### Technology Stack
- **Ansible** — orchestration layer; roles replace the former `setup.sh`
- **`kubernetes.core.helm`** — deploys Helm charts directly (no Kustomize needed)
- **`kubernetes.core.k8s`** — applies all Kubernetes manifests (namespaces, CRs, etc.)
- **`kubernetes.core.k8s_info`** — polls cluster state (CRD readiness, secret availability, Gateway IP)
- **MetalLB** — Layer 2 LoadBalancer; assigns IPs from pool `192.168.1.200–192.168.1.205`
- **Envoy Gateway** — Kubernetes Gateway API controller (v1.1.0); handles ingress and TLS termination
- **cert-manager** — issues and renews TLS certs from an internal self-signed Root CA (ECDSA-256)

### Project Structure

```
src/
├── main.yaml                        # Primary Ansible playbook (2 plays)
├── ansible.cfg                      # Ansible config (beautiful_output callback)
├── hosts.yaml                       # Inventory: localhost (connection: local)
├── requirements.yml                 # Galaxy collection: kubernetes.core
├── group_vars/all.yml               # Global vars
├── callback_plugins/
│   └── beautiful_output.py          # Aesthetic output plugin
└── roles/
    ├── cluster-setup/               # Full cluster bootstrap (infra + networking + TLS + CA trust)
    │   ├── tasks/
    │   │   ├── main.yml             # Entry point: import_tasks for each section file
    │   │   ├── gateway-api-crds.yml # Installs Gateway API Standard CRDs (kubectl apply -f URL)
    │   │   ├── helm-charts.yml      # Deploys MetalLB, Envoy Gateway, cert-manager via kubernetes.core.helm
    │   │   ├── wait-for-crds.yml    # Polls until each critical CRD is Established
    │   │   ├── cert-renewal-guard.yml # Detects and removes stale wildcard TLS secret
    │   │   ├── base-configs.yml     # Applies gateway ns, IP pool, GatewayClass, Gateway, PKI, wildcard cert
    │   │   ├── root-ca-trust.yml    # Extracts Root CA; installs into OS + browser NSS databases
    │   │   └── gateway-status.yml   # Polls and displays the Gateway's assigned LoadBalancer IP
    │   ├── handlers/main.yml        # CA trust update handlers (update-ca-trust / update-ca-certificates)
    │   └── files/                   # Kubernetes manifests applied by cluster-setup
    │       ├── gateway-namespace.yaml    # 'gateway' namespace (for Gateway + TLS cert)
    │       ├── metallb-config.yaml       # IPAddressPool + L2Advertisement
    │       ├── gatewayclass.yaml         # EnvoyProxy GatewayClass (cluster-scoped)
    │       ├── cert-manager-issuer.yaml  # self-signed Issuer + Root CA + ClusterIssuer
    │       ├── certificate.yaml          # Wildcard cert for *.frank.lab.io (namespace: gateway)
    │       └── gateway-api-instance.yaml # Gateway HTTP + HTTPS listeners (namespace: gateway)
    └── podinfo/                     # Demo application (role name = namespace name)
        ├── tasks/main.yml           # Single loop: namespace.yaml + all app resources
        └── files/                   # Application manifests (namespace: podinfo)
            ├── namespace.yaml       # 'podinfo' namespace — first item in the deploy loop
            ├── deployment.yaml      # podinfo Deployment
            ├── service.yaml         # podinfo ClusterIP Service
            └── httproute.yaml       # HTTPRoute: hello.frank.lab.io → my-gateway (gateway ns)
```

### Tags for granular runs
| Tag | Scope |
|---|---|
| `setup` | Everything (full deploy) |
| `infra` | `cluster-setup` role only (no apps) |
| `apps` | All app roles |
| `podinfo` | `podinfo` role only |
| `ca-trust` | Root CA OS/browser trust tasks only (subset of `cluster-setup`) |

### Certificate Trust Flow
`cert-manager` generates a Root CA and stores it in the `homelab-ca-tls` Secret. The `cluster-setup` role extracts it and installs it into:
- **Arch Linux**: `/etc/ca-certificates/trust-source/anchors/` → `update-ca-trust`
- **Ubuntu/Debian**: `/usr/local/share/ca-certificates/` → `update-ca-certificates`
- **Browsers** (if `certutil` is available): injected into Chrome/Firefox NSS databases automatically

Generated `*.crt` files are gitignored.

## Ansible Conventions

Follows the same conventions as `homelab-iac`:
- **Task names**: always in double quotes, written in English
- **Inventory format**: YAML only — `.ini` format is prohibited
- **Module priority**: always prefer `kubernetes.core.*` over `ansible.builtin.command`/`shell`; use `command` only when a module genuinely cannot do the job (e.g., `kubectl apply -f <url>` for a 50+ document CRD bundle)
- **Idempotency**: all roles must be safe to run multiple times
- **`gather_facts`**: set `false` by default; `cluster-setup` uses `true` because CA trust installation requires OS detection (`ansible_distribution`)

### Adding a New Application
Each application is its own role. **Role name = namespace name = app name** (convention).

1. **Add an entry to `apps` in `src/group_vars/all.yml`** — this is the source of truth:
   ```yaml
   apps:
     - name: my-app
       namespace: my-app
       domain: my-app.frank.lab.io
   ```
2. Create `src/roles/<name>/files/namespace.yaml` with `metadata.name: <name>`
3. Add `deployment.yaml`, `service.yaml`, `httproute.yaml` to `src/roles/<name>/files/` with `namespace: <name>`
4. The `HTTPRoute` must reference `{{ gateway_name }}` via `parentRefs[0]: {name: my-gateway, namespace: gateway}`
5. Create `src/roles/<name>/tasks/main.yml`: load `app` from the `apps` list with `set_fact`, then one looped `kubernetes.core.k8s` task (namespace.yaml first, then the rest)
6. Add the role to the "Deploy applications" play in `src/main.yaml` with tags `[setup, apps, <name>]`

## Namespace Layout

No resources are placed in the `default` namespace. Each concern has its own namespace:

| Namespace | Contents |
|---|---|
| `metallb-system` | MetalLB controller (created by Helm) |
| `envoy-gateway-system` | Envoy Gateway controller (created by Helm) |
| `cert-manager` | cert-manager controller (created by Helm) |
| `gateway` | Gateway instance + wildcard TLS certificate/secret |
| `podinfo` | podinfo Deployment, Service, HTTPRoute |
| `<app-name>` | any future application role |

## Key Domain
Internal services are exposed under `*.frank.lab.io` via the Gateway (`gateway` namespace) with a wildcard TLS listener. The Gateway IP is assigned from MetalLB's pool (`192.168.1.200–192.168.1.205`) and displayed at the end of the `cluster-setup` role.

## Gotchas

- The **beautiful_output** callback plugin can hide error details — run `just plugin off` when debugging
- `kubernetes.core` collection requires the `kubernetes` Python library (`pip3 install kubernetes`)
- `beautiful_output.py` requires the `watchdog` Python library
- Pre-commit hook auto-enables the aesthetic plugin; run `just install-hooks` after modifying `scripts/pre-commit.sh`
- CA trust installation tasks use `become: true` at the task level (not the play level)
- `just install-ca` (`--tags ca-trust`) assumes the cluster is already deployed; it only re-runs the CA extraction and local trust installation steps
