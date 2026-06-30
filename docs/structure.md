# Repository structure

```text
apps/
  adguard-home/
  authentik/
  netbird/
    argocd.yaml
    README.md
    base/
      resources.yaml          workloads, Services, routes and Cilium policies
    overlays/dev/
      kustomization.yaml      active Dev substitutions
docs/
  architecture.md
  structure.md
```

The shared Cilium Gateway and certificates live in `public-cluster-nix`.
Application HTTP/gRPC exposure lives here as `HTTPRoute` and `GRPCRoute`.
Kubernetes `Ingress`, `NetworkPolicy`, Traefik resources and HTTP NodePorts are
forbidden and checked by `cluster-testing/public-cluster/kubernetes/validate.sh`.
