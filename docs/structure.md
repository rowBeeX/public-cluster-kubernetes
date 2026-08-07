# Repository structure

```text
apps/
  adguard-home/               DNS/UI, NetBird-internal only (Envoy route locked to NetBird via SecurityPolicy)
  authentik/                  public OIDC provider (Envoy Gateway)
  mail-edge/                  Mail Edge / MX Relay (SMTP :25 inbound + outbound relay via Envoy :2525)
  netbird/                    dashboard/management/signal/relay (Envoy Gateway)
  postgresql/                 CNPG cluster backing Authentik
  valkey/                     cache/session store backing Authentik

  <app>/                      every app directory has the same flat layout:
    argocd.yaml               Argo CD marker file discovered by the ApplicationSet
    README.md
    kustomization.yaml        lists the manifests in the order below
    namespace.yaml            Namespace, LimitRange, ResourceQuota
    workload.yaml             workloads, Services, PVCs, Certificates, Vault* …
    networkpolicy.yaml        CiliumNetworkPolicies (default-deny + allow)
docs/
  app-layout.md
  architecture.md
  exceptions.md
  structure.md
```

There are no `base/` or `overlays/` directories: production is the only
environment, so every app is a single flat kustomize directory that Argo CD syncs
from `apps/<name>`. An app may add further manifests next to the three above
(for example `apps/mail-edge/tcproute.yaml`); `kustomization.yaml` lists them.

The Envoy Gateway and certificates live in `public-cluster-nix`. Application
HTTP/gRPC/WebSocket exposure lives here as `HTTPRoute` and `GRPCRoute` on the
Envoy Gateway; inbound Mail, STUN and DNS use protocol-specific Services, not
Envoy (only the outbound smarthost path is a `TCPRoute` on the NetBird-only
Envoy listener `:2525`).
Kubernetes `Ingress`, `NetworkPolicy`, Traefik resources and HTTP NodePorts are
forbidden and checked by `cluster-testing/public-cluster/kubernetes/validate.sh`.

## Documentation language

User-facing docs and READMEs are written in **English**; inline operator notes
and code comments may be German. Within a single sentence or paragraph, do not
mix languages.
