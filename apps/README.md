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
- HTTP wird ausschließlich per `HTTPRoute` an das Cilium Dev-Gateway gebunden.
- STUN/DNS-Sonderprotokolle bleiben explizite Cilium Services.
- Secrets kommen ausschließlich aus SOPS (via `public-cluster-nix/secrets/`)
