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
| `postgresql` | `app-postgresql` | CNPG-PostgreSQL-Cluster (Datenbank-Backend für Authentik) |
| `valkey` | `app-valkey` | Redis-kompatibler Cache/Session-Store (Backend für Authentik) |

## Konventionen

- Ressourcen je App aufgeteilt direkt im App-Verzeichnis (`namespace.yaml` → `workload.yaml` → `networkpolicy.yaml`), siehe [`docs/app-layout.md`](../docs/app-layout.md)
- Es gibt nur eine Umgebung, deshalb keine `base/`- oder `overlays/`-Ebene:
  ArgoCD synchronisiert `apps/<name>` direkt.
- HTTP wird ausschließlich per `HTTPRoute` an das Envoy-Gateway (`public`
  in `gateway-system`) gebunden.
- SMTP und STUN nutzen explizite Cilium Node IPAM Services auf den
  Gateway-Node-Adressen; deren LoadBalancer-NodePorts sind deaktiviert.
- Secrets stehen nie in diesem Repo: sie kommen aus Vault über den Vault
  Secrets Operator (`VaultAuth`/`VaultStaticSecret`) oder aus dem
  SOPS-gestützten Bootstrap in `public-cluster-nix`
