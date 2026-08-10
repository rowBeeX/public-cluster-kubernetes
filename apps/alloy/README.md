# Alloy

Sammelt Pod-Logs und Kubernetes-Metriken des Public-Clusters und liefert beides
an den **lokalen** Cluster — dort steht die einzige Loki- und
Prometheus-Instanz.

## Was hier läuft (und was nicht)

| Strom | Quelle | Ziel |
|-------|--------|------|
| Pod-Logs, alle Namespaces | Kubernetes-API (`pods/log`) | `https://loki.local.sedware.net/loki/api/v1/push`, `cluster="public"` |
| kubelet + cAdvisor, beide Nodes | API-Server-Proxy `/api/v1/nodes/<n>/proxy/metrics[/cadvisor]` | `https://prometheus.local.sedware.net/api/v1/write`, `cluster="public"` |
| kube-state-metrics | Sidecar auf `127.0.0.1:8080` | dito |

**Nicht** hier: das Host-Journal und die node_exporter-Metriken. Die liefert der
NixOS-Dienst aus `public-cluster-nix/modules/observability/alloy-journal.nix`,
und zwar absichtlich: Wenn k3s ausfällt, läuft dieser Pod nicht mehr — genau
dann braucht man die Journal-Zeilen.

## Besonderheiten

- **Deployment mit einer Replik, kein DaemonSet.** Beide Quellen sind
  node-übergreifend erreichbar. Zwei Agenten würden jede Logzeile doppelt nach
  Loki schicken und für dieselbe Node-Serie zwei Remote-Write-Sender erzeugen.
  Aus demselben Grund `strategy: Recreate`.
- **Kein hostPath, kein root.** `loki.source.kubernetes` liest über die API,
  deshalb erfüllt der Namespace `pod-security.kubernetes.io/enforce: restricted`
  und steht nicht in `docs/exceptions.md`.
- **Multi-Arch-Digest.** Host 2 ist aarch64; der Alloy-Digest ist der
  Index-Digest, nicht der amd64-Child-Digest aus `local-cluster-kubernetes`.
- **Serienbudget.** Vor `prometheus.remote_write` steht eine `keep`-Liste
  (`prometheus.relabel "budget"`). Der empfangende Prometheus lief auf einem
  Node mit 30 GiB RAM bei ~332 000 Serien und startete deswegen alle 31 Minuten
  neu. Zusätzlich beschränkt `--resources=…` kube-state-metrics an der Quelle
  (kein leases/endpointslices/configmaps/secrets), und eine zweite Regel wirft
  cAdvisor-Serien ohne `pod`-Label weg (Host-Cgroups; Host-Metriken kommen vom
  node_exporter des NixOS-Dienstes).
- **Stream-Labels identisch zum lokalen Cluster.** Die acht
  `discovery.relabel "pods"`-Regeln sind zeichengleich aus
  `local-cluster-kubernetes/apps/alloy/values.yaml` übernommen. Abweichende
  Labels brechen clusterübergreifende Grafana-Queries lautlos.

## Zugangsdaten

Loki-Push und Prometheus-Remote-Write sind mit Basic-Auth geschützt
(SecurityPolicies `loki-ingest` / `prometheus-ingest` im lokalen Cluster).
Benutzer ist `public-cluster` — derselbe wie beim NixOS-Alloy-Dienst. Das
Klartext-Passwort kommt aus dem Public-Vault (`secret/apps/app-alloy/ingest`,
Key `password`) über `VaultStaticSecret` und liegt im Pod unter
`/etc/alloy-secrets/password`. Quelle der Wahrheit ist
`observability/alloy_ingest_password` in der SOPS-Datei von
`public-cluster-host-1`; ein abweichender Wert liefert HTTP 401 und stillen
Telemetrieverlust.

## Prüfen

```bash
kubectl -n app-alloy get deploy alloy
kubectl -n app-alloy logs deploy/alloy -c alloy --tail=50   # keine "final error sending batch"
```

Im lokalen Cluster muss danach `count by(cluster, job)(up)` neben
`cluster="local"` auch `cluster="public"` mit den Jobs `kubelet` und
`kube-state-metrics` liefern, und Loki muss unter `cluster="public"` die
Public-Namespaces kennen.
