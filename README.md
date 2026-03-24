# Homelab Deploys

<p align="left">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/K3s-326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white" alt="K3s"/>
</p>

## Overview

The **Homelab Deploys** project is responsible for managing the software layer and workloads running on the personal Kubernetes (K3s) cluster. While the `homelab-iac` repository handles the raw infrastructure (VMs and Proxmox), this project focuses on orchestrating networking services, security components, and applications.

It uses a modern approach based on **Kustomize** to integrate Helm Charts and native manifests, enabling declarative and reproducible cluster management.

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
| **cert-manager** | Automatic TLS certificate issuance via Self-Signed and ClusterIssuer. |
| **Podinfo** | Demo application used to validate the entire stack's functionality. |

---

## How to Use

### Prerequisites
- A functional Kubernetes cluster (installed via `homelab-iac`).
- `kubectl`, `helm`, and `kustomize` installed on your local machine.

### Installation
The deployment process is fully automated via the `setup.sh` script. it handles the correct installation order, from CRDs to certificate trust configuration.

```bash
# Navigate to the source directory
cd homelab-deploys/src

# Execute the setup script
./setup.sh
```

**What the script does for you:**
1. Creates the necessary Namespaces.
2. Installs the Standard Gateway API CRDs.
3. Deploys Helm Charts (MetalLB, Envoy, cert-manager) via Kustomize.
4. Configures the IP pool and the Gateway.
5. Extracts the internal Root CA.
6. **Installs the certificate on your local host** (supports Arch, Ubuntu, Debian, and NSS databases).

---

## Project Structure

- `src/apps/`: Application manifests (e.g., `podinfo`).
- `src/infra/`: Base infrastructure configuration.
  - `base/`: Custom resources (Gateways, Certificates, IP Pools).
  - `charts/`: Location where Helm Charts are processed.
- `src/setup.sh`: Master automation and trust configuration script.

---

## License

Distributed under the [CC BY-NC-SA 4.0](http://creativecommons.org/licenses/by-nc-sa/4.0/) license.
