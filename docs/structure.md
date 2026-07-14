# Repository structure

```text
apps/
  adguard-home/               DNS/UI, NetBird-internal only (Envoy route locked to NetBird via SecurityPolicy)
  authentik/                  public OIDC provider (Envoy Gateway)
  local-nginx-proxy/          public edge entry for the local cluster's nginx (re-encrypt over NetBird)
  mail-edge/                  Mail Edge / MX Relay (SMTP :25 inbound + outbound relay via Envoy :2525)
  netbird/                    dashboard/management/signal/relay (Envoy Gateway)
  postgresql/                 CNPG cluster backing Authentik
  public-nginx/               public nginx test server (Envoy Gateway)
  valkey/                     cache/session store backing Authentik
    argocd.yaml
    README.md
    base/
      namespace.yaml          Namespace, LimitRange, ResourceQuota
      workload.yaml           workloads, Services, PVCs, Certificates, Vault* …
      networkpolicy.yaml      CiliumNetworkPolicies (default-deny + allow)
    overlays/dev/
      kustomization.yaml      active Dev substitutions
    overlays/prod/
      kustomization.yaml      Prod substitutions
docs/
  architecture.md
  structure.md
```

The Envoy Gateway and certificates live in `public-cluster-nix`. Application
HTTP/gRPC/WebSocket exposure lives here as `HTTPRoute` and `GRPCRoute` on the
Envoy Gateway; Mail, STUN and DNS use protocol-specific Services, not Envoy.
Kubernetes `Ingress`, `NetworkPolicy`, Traefik resources and HTTP NodePorts are
forbidden and checked by `cluster-testing/public-cluster/kubernetes/validate.sh`.

## Documentation language

User-facing docs and READMEs are written in **English**; inline operator notes
and code comments may be German. Within a single sentence or paragraph, do not
mix languages.
