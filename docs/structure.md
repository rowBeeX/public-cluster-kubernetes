# Repository structure

```text
apps/
  adguard-home/               DNS/UI, NetBird-internal only (Envoy route locked to NetBird via SecurityPolicy)
  authentik/                  public OIDC provider (Envoy Gateway)
  local-nginx-proxy/          public edge entry for the local cluster's nginx (re-encrypt over NetBird)
  mail-edge/                  Mail Edge / MX Relay (SMTP :25, public in/out)
  netbird/                    dashboard/management/signal/relay (Envoy Gateway)
  postgresql/                 CNPG cluster backing Authentik
  public-nginx/               public nginx test server (Envoy Gateway)
  valkey/                     cache/session store backing Authentik
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

The Envoy Gateway and certificates live in `public-cluster-nix`. Application
HTTP/gRPC/WebSocket exposure lives here as `HTTPRoute` and `GRPCRoute` on the
Envoy Gateway; Mail, STUN and DNS use protocol-specific Services, not Envoy.
Kubernetes `Ingress`, `NetworkPolicy`, Traefik resources and HTTP NodePorts are
forbidden and checked by `cluster-testing/public-cluster/kubernetes/validate.sh`.
