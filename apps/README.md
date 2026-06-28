# Apps — Public Cluster

Kubernetes-Manifeste für die drei öffentlichen Cluster-Apps. Deployment erfolgt
über ArgoCD (ApplicationSet aus `public-cluster-nix`).

## Apps

| App | Namespace | Funktion |
|-----|-----------|----------|
| `authentik` | `app-authentik` | OIDC-Provider für alle Cluster-Dienste |
| `netbird` | `app-netbird` | WireGuard-VPN-Management (Server + Dashboard) |
| `adguard-home` | `app-adguard-home` | DNS-Resolver mit Rewrite-Regeln |

## Konventionen

- Alle Ressourcen je App in einer monolithischen `base/resources.yaml`
- Overlays: `overlays/dev/` (aktive Generation), `overlays/prod/` noch nicht vorhanden
- NodePort-Services für HAProxy-Routing sind in `public-cluster-nix` definiert,
  nicht hier — siehe `modules/kubernetes/manifests/platform/nodeports/services.yaml`
- Secrets kommen ausschließlich aus SOPS (via `public-cluster-nix/secrets/`)
