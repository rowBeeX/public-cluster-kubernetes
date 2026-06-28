---
name: kubernetes
description: Operate and diagnose the public k3s cluster and its Argo CD applications.
---

# Public k3s cluster

- Run Kubernetes commands through `public-cluster-host-1` with
  `sudo k3s kubectl`; never use an unrelated local context.
- Git is the source of truth. Do not persistently patch Argo CD-managed
  resources live.
- Host 1 is the single control plane; Host 2 is an agent. This is deliberately
  not HA.
- Public ingress is HAProxy -> host-network Traefik -> Kubernetes Service.
- Use `public-shared-bulk` only for shared bulk/RWX data. Keep databases on
  explicit node-local storage unless their own HA design says otherwise.
- Never print Secret values. Inspect only names, conditions and events.
- Validate overlays with `scripts/validate.sh`, then inspect nodes, pods,
  Applications, events and relevant logs on Host 1.
