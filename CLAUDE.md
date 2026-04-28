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
just secrets-keygen    # Generate vault password at ~/.config/homelab-iac/.vault_pass
just secrets-edit      # Edit encrypted vault.yml (decrypt → edit → re-encrypt)
just init              # Install hooks + Ansible Galaxy collections + check dependencies

# Deployment
just deploy            # Full deploy (namespaces + CRDs + infra + apps + Root CA trust)
just deploy-infra      # Only infra layer (namespaces, CRDs, Helm charts, base configs)
just deploy-apps       # Only applications (podinfo and any new apps)
just install-ca        # Only install Root CA into OS trust store and browser NSS databases

# Teardown
just destroy           # Full teardown (stops node_exporter + wipes cluster namespaces)

# PR Review
just pr-review         # Interactive TUI to browse, approve, and merge PRs (requires gum)
just pr-list           # Non-interactive PR listing (for scripting / Claude)

# Secrets
just secrets-view      # View decrypted vault.yml in terminal
just secrets-encrypt   # Encrypt vault.yml (run before committing if manually decrypted)
just secrets-decrypt   # Decrypt vault.yml permanently (use with caution)

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
- **`src/roles/`** — Self-contained roles; each owns its Kubernetes manifests in `files/`
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
    ├── podinfo/                     # Demo application (role name = namespace name)
    │   ├── tasks/main.yml           # Single loop: namespace.yaml + all app resources
    │   └── files/                   # Application manifests (namespace: podinfo)
    │       ├── namespace.yaml       # 'podinfo' namespace — first item in the deploy loop
    │       ├── deployment.yaml      # podinfo Deployment
    │       ├── service.yaml         # podinfo ClusterIP Service
    │       └── httproute.yaml       # HTTPRoute: hello.frank.lab.io → my-gateway (gateway ns)
    ├── monitoring/                  # Prometheus + Loki + Promtail (ns: prometheus, loki)
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── kube-prometheus-stack-values.yaml.j2
    │       ├── loki-values.yaml.j2
    │       └── prometheus-httproute.yaml.j2
    └── grafana/                     # Grafana standalone + all dashboard ConfigMaps (ns: grafana)
        ├── tasks/main.yml           # Helm install + dashboard ConfigMaps + HTTPRoute
        ├── templates/
        │   ├── grafana-values.yaml.j2
        │   └── grafana-httproute.yaml.j2
        └── files/dashboards/        # Dashboard JSON files (plain .json, ConfigMaps built inline)
            ├── cluster-logs.json
            ├── pod-logs.json
            └── proxmox-node.json
```

### Tags for granular runs
| Tag | Scope |
|---|---|
| `setup` | Everything (full deploy) |
| `infra` | `cluster-setup` role only (no apps) |
| `apps` | All app roles |
| `podinfo` | `podinfo` role only |
| `monitoring` | `monitoring` role only (Prometheus + Loki + Promtail) |
| `grafana` | `grafana` role only (Grafana install + all dashboards) |
| `proxmox-node` | node_exporter install on Proxmox host only |
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
- **Module priority**: always prefer `kubernetes.core.k8s` / `kubernetes.core.k8s_info` for applying and querying manifests. **Never use `kubernetes.core.helm`** — it has version compatibility issues with the local Helm CLI; use `ansible.builtin.command` with `helm upgrade --install` instead (idempotent, predictable, matches the pattern in `cluster-setup/tasks/helm-charts.yml`). Use `ansible.builtin.command` / `shell` only when no module can genuinely do the job (e.g., `kubectl apply -f <url>` for a multi-document CRD bundle).
- **Idempotency**: all roles must be safe to run multiple times
- **`gather_facts`**: set `false` by default; `cluster-setup` uses `true` because CA trust installation requires OS detection (`ansible_distribution`)
- **Loop over identical tasks**: never write multiple tasks that do the same thing differing only in the target resource. Collapse them into a single `kubernetes.core.k8s` task with `loop` + `loop_control.label`. See `roles/podinfo/tasks/main.yml` and `roles/monitoring/tasks/main.yml` as reference.

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
7. **Add the app to the Homepage dashboard** — add an entry in `src/roles/homepage/templates/config-services.yaml.j2` under the appropriate group (Aplicações, Monitoramento, Infraestrutura, or Rede)

## Namespace Layout

No resources are placed in the `default` namespace. Each concern has its own namespace:

| Namespace | Contents |
|---|---|
| `metallb-system` | MetalLB controller (created by Helm) |
| `envoy-gateway-system` | Envoy Gateway controller (created by Helm) |
| `cert-manager` | cert-manager controller (created by Helm) |
| `gateway` | Gateway instance + wildcard TLS certificate/secret |
| `podinfo` | podinfo Deployment, Service, HTTPRoute |
| `prometheus` | kube-prometheus-stack (Prometheus + Alertmanager + kube-state-metrics + node-exporter) |
| `grafana` | Grafana standalone (dashboards + datasources for Prometheus and Loki) |
| `loki` | Loki (log aggregation) + Promtail (log collector DaemonSet) |
| `longhorn-system` | Longhorn distributed block storage (created by Helm) |
| `<app-name>` | any future application role |

### Longhorn (Distributed Block Storage)
Role: `src/roles/longhorn/`. Deployed via Helm as part of the infra layer (`--tags infra`). No manifests in `files/` — fully Helm-managed. PVCs from other roles request `longhorn` StorageClass.

## Proxmox Host Monitoring

`node_exporter` runs as a systemd service directly on the Proxmox host (`192.168.1.115`). A companion bash script (`proxmox-vm-metrics.sh`) runs every 30 seconds via a systemd timer and writes per-VM/LXC metrics in Prometheus textfile format to `/var/lib/node_exporter/textfile/proxmox_guests.prom`. Prometheus scrapes `:9100` with `job_name: proxmox-node`.

- Role: `src/roles/proxmox-node/` — manages binary install, systemd units
- The Proxmox dashboard (`proxmox-node.json`) lives in the `grafana` role (`files/dashboards/`) and is applied there
- Destroy: `just destroy` stops/removes node_exporter from the host before wiping cluster namespaces

## Key Domain
Internal services are exposed under `*.frank.lab.io` via the Gateway (`gateway` namespace) with a wildcard TLS listener. The Gateway IP is assigned from MetalLB's pool (`192.168.1.200–192.168.1.205`) and displayed at the end of the `cluster-setup` role.

## Secrets Management

- `src/group_vars/all/vault.yml` is **always encrypted** in Git — the pre-commit hook blocks unencrypted commits
- Vault password lives at `~/.config/homelab-iac/.vault_pass` (must be `chmod 600`)
- Use `just secrets-edit` for all edits (atomic decrypt/edit/re-encrypt)
- If you manually decrypt, always run `just secrets-encrypt` before committing
- All `ansible-playbook` invocations automatically pass `--vault-password-file` via `ansible_cmd`

### Manipulating vault.yml programmatically (Claude)

To add or update secrets in `vault.yml` without the interactive editor:
1. `just secrets-decrypt` — decrypt in place
2. Edit `src/group_vars/all/vault.yml` with the Edit/Write tool
3. `just secrets-encrypt` — re-encrypt before any commit

Never leave `vault.yml` decrypted after editing. Always run step 3 immediately after step 2.

## Renovate Maintenance

Whenever a version variable is added or modified in `src/group_vars/all/vars.yml`, add or update the corresponding `customManagers` entry in `renovate.json` so Renovate can track and auto-update it. Each entry needs: `fileMatch` pointing to `vars.yml`, a `matchStrings` regex capturing the version value, and the correct `datasourceTemplate` + `depNameTemplate` + `registryUrlTemplate` for the upstream source (Helm registry, GitHub releases, or Docker registry).

## README Maintenance

Whenever a structural change is made to the project — new role, new `just` command, changed prerequisites, updated project layout, or new secrets workflow — **review and update `README.md`** to keep it in sync. The README is the public-facing entry point and must always reflect the actual state of the codebase.

## Destroy Maintenance

Whenever the deploy changes — new role, new namespace, or new operator (Helm chart that registers webhooks/CRDs with finalizers) — **review and update `src/destroy.yaml`** to keep it in sync. Specifically check:

1. **`all_namespaces` list** — every namespace created by `just deploy` must be listed so it gets deleted and waited on
2. **Webhook pre-cleanup** — if the new operator registers a `ValidatingWebhookConfiguration` or `MutatingWebhookConfiguration`, add it to the "Remove operator webhook configurations" task; otherwise its CRs will be stuck in Terminating after the operator is gone
3. **Finalizer-strip tasks** — if the new operator's CRs carry finalizers that only the controller can process (e.g., Longhorn's `longhorn.io`, CNPG's `cnpg.io/deleteDatabase`), add a shell task to patch those finalizers to `[]` before namespace deletion
4. **CRD cleanup** — if the operator's CRDs embed `webhookClientConfig` (Longhorn, CNPG do), add a shell task to delete those CRDs by label/suffix; stale CRDs cause `helm upgrade --install` to fail on the next deploy

## Session Start — Renovate PR Triage

When the session starts and the context contains `RENOVATE_PRS_PENDING`, perform this triage automatically (no need to ask the user):

1. **Fetch full PR list** — run `just pr-list` (calls `scripts/pr-review.sh --list`), which outputs all open PRs with title, author, URL, and body in a readable format.
2. **Evaluate each PR** — A PR is safe to approve if it is a routine version bump (Helm chart version, GitHub Action pinned SHA, dependency patch/minor) with no breaking-change notes in the body. Skip (do not approve) if the body mentions breaking changes, deprecations, or major version jumps that require config changes.
3. **Approve safe PRs** — `gh pr review <number> --approve --repo frankjuniorr/homelab-deploys`
4. **Sync local branch** — `git pull` after all PRs are handled
5. **Report** — Briefly list which PRs were approved and which were skipped (and why)

Use the `git-specialist` sub-agent (via `Agent` tool) for any `gh` operations if the triage is complex.

> **Standalone usage:** `just pr-review` launches the full interactive TUI (requires `gum`) where you can browse PRs, read their body, and approve or merge with keyboard navigation.

## Skills

Always invoke the appropriate skill via the `Skill` tool before doing work that matches one of the entries below. Do not duplicate what the skill already does.

| Trigger | Skill / Agent |
|---|---|
| **Any Kubernetes troubleshooting** (pod crashes, CrashLoopBackOff, service connectivity, cert-manager, gateway, Helm failures, node pressure) | sub-agent `k8s-troubleshooter` (via `Agent` tool) |
| Creating/editing Kubernetes manifests, debugging pod crashes, resource limits, network policies | `kubernetes-specialist` |
| Writing Dockerfiles, CI/CD pipelines, GitHub Actions, infrastructure-as-code | `devops-engineer` |
| Setting up observability, deployment strategies, container configuration | `devops-infrastructure` |
| Committing changes, writing commit messages | sub-agent `git-specialist` (via `Agent` tool) |
| Any `gh` CLI operation (issues, PRs, releases, checks) | sub-agent `git-specialist` (via `Agent` tool) |
| Refactoring Ansible roles or any code for maintainability | `refactor` |
| Updating or creating `README.md` | `create-readme` |
| Improving or auditing `CLAUDE.md` | `claude-md-improver` |
| Diagnosing Linux/Arch Linux system issues (pacman, systemd, boot, filesystem, network, performance) | sub-agent `linux-specialist` (via `Agent` tool) |
| Cross-layer homelab issues (Proxmox + K3s + networking + monitoring) | sub-agent `homelab-troubleshooter` (via `Agent` tool) |

## Gotchas

- The **beautiful_output** callback plugin can hide error details — run `just plugin off` when debugging
- `kubernetes.core` collection requires the `kubernetes` Python library (`pip3 install kubernetes`)
- `beautiful_output.py` requires the `watchdog` Python library
- Pre-commit hook checks vault encryption and auto-enables the aesthetic plugin; run `just install-hooks` after modifying `scripts/pre-commit.sh`
- CA trust installation tasks use `become: true` at the task level (not the play level)
- `just install-ca` (`--tags ca-trust`) assumes the cluster is already deployed; it only re-runs the CA extraction and local trust installation steps
