# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repo manages the **software/workload layer** of a personal K3s (lightweight Kubernetes) cluster. It is a companion to `homelab-iac` (which handles raw Proxmox infrastructure). Everything here deploys into a running K3s cluster.

## Deployment

The single entry point is:

```bash
cd src && ./setup.sh
```

This script does everything in order:
1. Creates namespaces (`metallb-system`, `envoy-gateway-system`, `cert-manager`)
2. Installs Gateway API CRDs (v1.1.0)
3. Deploys Helm charts via Kustomize (MetalLB, Envoy Gateway, cert-manager)
4. Applies base infra configs and manages certificate lifecycle
5. Deploys the Podinfo demo app
6. Extracts and installs the Root CA into the OS trust store and browser NSS databases

**Prerequisites:** `kubectl`, `helm`, `kustomize` must be available in PATH.

## Architecture

### Technology Stack
- **Kustomize** — manifest management; Helm charts are pulled inline via `helmCharts:` in `kustomization.yaml`
- **MetalLB** — Layer 2 LoadBalancer; assigns IPs from pool `192.168.1.200–192.168.1.205`
- **Envoy Gateway** — Kubernetes Gateway API controller (v1.1.0); handles ingress and TLS termination
- **cert-manager** — issues and renews TLS certs from an internal self-signed Root CA (ECDSA-256)

### Layered Structure

```
src/
├── setup.sh              # Master deployment script
├── infra/
│   ├── kustomization.yaml        # Helm chart declarations (MetalLB, Envoy, cert-manager)
│   └── base/
│       ├── kustomization.yaml    # Applies all base manifests
│       ├── metallb-config.yaml   # IP pool + L2Advertisement
│       ├── cert-manager-issuer.yaml  # Self-signed root CA + ClusterIssuer
│       ├── certificate.yaml      # Wildcard cert for *.frank.lab.io
│       ├── gatewayclass.yaml     # EnvoyProxy GatewayClass
│       └── gateway-api-instance.yaml # Gateway (HTTP/HTTPS listeners, TLS)
└── apps/
    └── podinfo/                  # Demo app with Deployment, Service, HTTPRoute
```

### Certificate Trust Flow
`cert-manager` issues certs from a self-signed root CA. `setup.sh` extracts the CA cert from the `homelab-ca-tls` secret and installs it into:
- **Arch Linux**: `/etc/ca-certificates/trust-source/anchors/` → `update-ca-trust`
- **Ubuntu/Debian**: `/usr/local/share/ca-certificates/` → `update-ca-certificates`
- **Browsers** (if `certutil` is available): injected into Chrome/Firefox NSS databases automatically

Generated `*.crt` files are gitignored.

### Adding a New Application
Follow the `apps/podinfo/` pattern:
1. Create `src/apps/<app>/` with `kustomization.yaml`, `deployment.yaml`, `service.yaml`
2. Add an `HTTPRoute` pointing to the Gateway (`frank-gateway` in `envoy-gateway-system`)
3. Reference the wildcard cert or request a new cert via cert-manager
4. Add the app directory to `setup.sh` Step 5

## Key Domain
Internal services are exposed under `*.frank.lab.io` via the Gateway's wildcard TLS listener. The Gateway IP is assigned from MetalLB's pool and printed at the end of `setup.sh`.
