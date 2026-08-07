# Public Cluster Kubernetes

Argo-CD-Applikationsquelle für den Sedware Public-k3s-Cluster. Cilium-
Dataplane, Gateway API, cert-manager, CrowdSec und Argo CD selbst werden vom
Schwester-Repository `public-cluster-nix` verwaltet.

Hier verwaltete Applikationen:

- `authentik`: öffentlicher Identity-Provider;
- `postgresql`: CNPG-PostgreSQL-Cluster als Backend für Authentik;
- `valkey`: Redis-kompatibler Cache-/Session-Store als Backend für Authentik;
- `netbird`: selbst gehostetes Control-Plane und Dashboard;
- `adguard-home`: NetBird-only DNS und Administrations-UI;
- `mail-edge`: Mail Edge / MX-Relay (SMTP :25) vor dem Local-Stalwart-Backend.

WordPress ist bewusst noch nicht deployt. Künftige öffentliche Applikationen
können die RWX-StorageClass `public-shared-bulk` nutzen; Datenbank-Workloads
sollten weiterhin node-lokalen SSD-Storage verwenden, sofern kein
applikationsspezifisches HA-Datenbankdesign eingeführt wird.

## Validierung

```bash
bash cluster-testing/public-cluster/kubernetes/validate.sh
```

Das Skript rendert jede App unter `apps/` und validiert die YAML-/Kustomize-
Struktur. Die Live-Validierung erfolgt über Argo CD und `sudo k3s kubectl` auf
`public-cluster-host-1`.
