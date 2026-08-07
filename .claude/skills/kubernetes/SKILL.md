---
name: kubernetes
description: Operate and diagnose the public k3s cluster and its Argo CD applications.
---

# Public k3s cluster

- Run Kubernetes commands through `public-cluster-host-1` with
  `sudo k3s kubectl`; never use an unrelated local context.
- Git is the source of truth. Do not persistently patch Argo CD-managed
  resources live.
- `public-cluster-host-1` is the single control plane;
  `public-cluster-host-2` is an agent and is not procured yet, so the cluster
  currently runs on Host 1 alone. This is deliberately not HA.
- HTTP path: external DNS (explicit A/AAAA records per public edge host under
  `sedware.net`, deliberately no public wildcard) -> public Envoy Gateway
  (`public` in namespace `gateway-system`, hostNetwork on the gateway
  nodes) -> HTTPRoute -> ClusterIP Service -> Pod. TLS is terminated at the
  Envoy Gateway with the cert-manager wildcard certificate `public-wildcard`
  (secret `public-wildcard-tls`, Cloudflare DNS-01).
  There is no HAProxy, Traefik, NodePort or Kubernetes Ingress in this path.
- Raw TCP/UDP special cases (NetBird STUN, Mail-Edge SMTP) are exposed through
  explicit Cilium Node-IPAM `LoadBalancer` Services (`loadBalancerClass:
  io.cilium/node`, NodePorts disabled), not through Envoy; `spec.externalIPs` is
  forbidden by the contract (`validate.sh` #7). AdGuard DNS :53 is hostNetwork
  over the NetBird overlay.
- Use `public-shared-bulk` (SMB CSI against a Hetzner StorageBox; there is no
  NFS here) only for shared bulk/RWX data. Keep databases on
  explicit node-local storage unless their own HA design says otherwise.
- Never print Secret values. Inspect only names, conditions and events.
- Validate the rendered apps with
  `cluster-testing/public-cluster/kubernetes/validate.sh`, then inspect nodes,
  pods, Applications, events and relevant logs on Host 1.
