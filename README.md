# Public Cluster Kubernetes

Argo-CD-Applikationsquelle für den Sedware Public-k3s-Cluster. Cilium-
Dataplane, Gateway API, cert-manager, CrowdSec und Argo CD selbst werden vom
Schwester-Repository `public-cluster-nix` verwaltet.

Die Liste der hier verwalteten Applikationen steht an genau einer Stelle:
[`apps/README.md`](apps/README.md).

Künftige öffentliche Applikationen können die RWX-StorageClass
`public-shared-bulk` nutzen; Datenbank-Workloads sollten weiterhin node-lokalen
SSD-Storage verwenden, sofern kein applikationsspezifisches HA-Datenbankdesign
eingeführt wird.

## Validierung

```bash
bash cluster-testing/public-cluster/kubernetes/validate.sh
```

Das Skript rendert jede App unter `apps/` und validiert die YAML-/Kustomize-
Struktur. Die Live-Validierung erfolgt über Argo CD und `sudo k3s kubectl` auf
`public-cluster-host-1`.
