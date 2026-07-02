# Repository structure

```text
apps/
  adguard-home/               DNS/UI, NetBird-internal only (no public route)
  authentik/                  public OIDC provider (Envoy Gateway)
  mail-edge/                  Mail Edge / MX Relay (SMTP :25, public in/out)
  netbird/                    dashboard/management/signal/relay (Envoy Gateway)
    argocd.yaml
    README.md
    base/
      resources.yaml          workloads, Services, routes and Cilium policies
    overlays/dev/
      kustomization.yaml      active Dev substitutions
  smoke/                      stateless public lightweight edge smoke app
docs/
  architecture.md
  structure.md
```

The Envoy Gateway and certificates live in `public-cluster-nix`. Application
HTTP/gRPC/WebSocket exposure lives here as `HTTPRoute` and `GRPCRoute` on the
Envoy Gateway; Mail, STUN and DNS use protocol-specific Services, not Envoy.
Kubernetes `Ingress`, `NetworkPolicy`, Traefik resources and HTTP NodePorts are
forbidden and checked by `cluster-testing/public-cluster/kubernetes/validate.sh`.
