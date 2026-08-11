# Apps — Public Cluster

Kubernetes-Manifeste für die öffentlichen Cluster-Apps. Deployment erfolgt
über ArgoCD (ApplicationSet aus `public-cluster-nix`).

Diese Tabelle ist die **einzige** App-Liste des Repositories; `README.md` und
`docs/structure.md` verweisen hierher.

## Apps

| App | Namespace | PSA | Funktion |
|-----|-----------|-----|----------|
| [`adguard-home`](adguard-home/) | `app-adguard-home` | privileged | DNS-Resolver mit Rewrite-Regeln, ausschließlich NetBird-intern (hostNetwork `:53`) |
| [`alloy`](alloy/) | `app-alloy` | restricted | Liefert Pod-Logs und Kubernetes-Metriken an Loki/Prometheus im lokalen Cluster |
| [`authentik`](authentik/) | `app-authentik` | restricted | Öffentlicher OIDC-Provider für alle Cluster-Dienste |
| [`gitlab-runner`](gitlab-runner/) | `app-gitlab-runner` | restricted | CI-Runner je Architektur (amd64/arm64) für das GitLab im lokalen Cluster |
| [`mail-edge`](mail-edge/) | `app-mailedge` | baseline | Mail Edge / MX-Relay (SMTP `:25`) vor dem Local-Stalwart-Backend |
| [`mail-wellknown`](mail-wellknown/) | `app-mail-wellknown` | restricted | Mozilla-Autoconfig-XML für den `.well-known/autoconfig`-Fallback am Apex (die `autoconfig.sedware.net`-Antwort selbst liegt in local-cluster-kubernetes) |
| [`netbird`](netbird/) | `app-netbird` | baseline | WireGuard-VPN-Management (Server + Dashboard) |
| [`postgresql`](postgresql/) | `app-postgresql` | restricted | CNPG-PostgreSQL-Cluster (Datenbank-Backend für Authentik) |
| [`valkey`](valkey/) | `app-valkey` | restricted | Redis-kompatibler Cache/Session-Store (Backend für Authentik) |

Jede PSA-Stufe außer `restricted` ist eine begründete Ausnahme und in
[`docs/exceptions.md`](../docs/exceptions.md) geführt;
`cluster-testing/public-cluster/kubernetes/validate.sh` erzwingt das.

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
