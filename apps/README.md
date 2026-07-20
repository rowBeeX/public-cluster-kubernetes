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
| `postgresql` | `app-postgresql` | CNPG-PostgreSQL-Cluster (Datenbank-Backend für Authentik) |
| `valkey` | `app-valkey` | Redis-kompatibler Cache/Session-Store (Backend für Authentik) |

## Konventionen

- Ressourcen je App aufgeteilt im `base/` (`namespace.yaml` → `workload.yaml` → `networkpolicy.yaml`), siehe [`docs/app-layout.md`](../docs/app-layout.md)
- Overlays: `overlays/dev/` (aktive Generation) und `overlays/prod/` je App vorhanden
- HTTP wird ausschließlich per `HTTPRoute` an das Envoy Dev-Gateway (`public-dev`
  in `gateway-system`) gebunden.
- SMTP und STUN nutzen explizite Cilium Node IPAM Services auf den
  Gateway-Node-Adressen; deren LoadBalancer-NodePorts sind deaktiviert.
- Secrets kommen ausschließlich aus SOPS (via `public-cluster-nix/secrets/`)
