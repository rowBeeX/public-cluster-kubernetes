# Apps — Public Cluster

Kubernetes-Manifeste für die öffentlichen Cluster-Apps. Deployment erfolgt
über ArgoCD (ApplicationSet aus `public-cluster-nix`).

## Apps

| App | Namespace | Funktion |
|-----|-----------|----------|
| `authentik` | `app-authentik` | OIDC-Provider für alle Cluster-Dienste |
| `netbird` | `app-netbird` | WireGuard-VPN-Management (Server + Dashboard) |
| `adguard-home` | `app-adguard-home` | DNS-Resolver mit Rewrite-Regeln |
| `mail-edge` | `app-mailedge` | Mail Edge / MX-Relay (SMTP :25) vor dem Local-Stalwart-Backend |
| `public-nginx` | `app-public-nginx` | Öffentlicher nginx-Testserver am Envoy-Edge |
| `local-nginx-proxy` | `app-local-nginx-proxy` | Öffentlicher Edge-Eingang, re-encrypt zum nginx des lokalen Clusters über NetBird |
| `smoke` | `app-smoke` | Smoke-Test-App (whoami), prüft den öffentlichen Envoy-Edge end-to-end (kein Produktivdienst) |

## Konventionen

- Alle Ressourcen je App in einer monolithischen `base/resources.yaml`
- Overlays: `overlays/dev/` (aktive Generation), `overlays/prod/` noch nicht vorhanden
- HTTP wird ausschließlich per `HTTPRoute` an das Cilium Dev-Gateway gebunden.
- STUN/DNS-Sonderprotokolle bleiben explizite Cilium Services.
- Secrets kommen ausschließlich aus SOPS (via `public-cluster-nix/secrets/`)
