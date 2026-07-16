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
- HTTP path: external Dev DNS (`*.dev10.sedware.net`) -> public Envoy Gateway
  (`public-dev` in namespace `gateway-system`, hostNetwork on both gateway
  nodes) -> HTTPRoute -> ClusterIP Service -> Pod. TLS is terminated at the
  Envoy Gateway with the cert-manager wildcard certificate (Cloudflare DNS-01).
  There is no HAProxy, Traefik, NodePort or Kubernetes Ingress in this path.
- Raw TCP/UDP special cases (e.g. NetBird STUN/TURN, AdGuard DNS) are exposed
  through explicit Cilium Services with `externalIPs`, not through Envoy.
- Use `public-shared-bulk` only for shared bulk/RWX data. Keep databases on
  explicit node-local storage unless their own HA design says otherwise.
- Never print Secret values. Inspect only names, conditions and events.
- Validate overlays with `cluster-testing/public-cluster/kubernetes/validate.sh`,
  then inspect nodes, pods,
  Applications, events and relevant logs on Host 1.
