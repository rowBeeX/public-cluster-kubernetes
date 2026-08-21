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
- **cert-manager wird seit 2026-08-12 mitgescrapt.** Davor kannte der zentrale
  Prometheus `certmanager_`-Serien nur mit `cluster="local"` — ein
  abgelaufenes oder hängendes Edge-Zertifikat dieses Clusters hätte also
  keinen Alarm ausgelöst, obwohl der Exporter auf `:9402` längst lief (104
  Serien gemessen).
- **WAL-Puffer für Loki.** `loki.write "central"` ohne `wal`-Block hält
  Zeilen nur im Speicher und wirft sie nach erschöpften Wiederholungen
  endgültig weg — gemessen 2026-08-19 bis 2026-08-21 fehlten deshalb 26 von 73
  Stundenfenstern vollständig in Loki. Der `wal`-Block ist experimentell
  (Alloy-Referenz `loki.write`) und verlangt deshalb
  `--stability.level=experimental` statt `generally-available`; keine der
  übrigen Komponenten hier nutzt experimentelle Syntax, die dadurch
  zusätzlich erreichbar würde. Der lokale Alloy braucht das nicht — er
  schreibt clusterintern, ohne den NetBird-Hop.
  Geprüft mit `alloy validate` und `alloy fmt` **im laufenden Pod** (exakt
  v1.18.1, siehe Prüfen unten): syntaktisch gültig auf allen drei
  Stability-Stufen — `validate` erzwingt die Stability-Gate nicht, das tut
  erst `alloy run`. Die Stability-Stufe von `wal` selbst steht in der
  Alloy-Referenzdokumentation, Tag v1.18.1: `experimental`, nicht
  `public-preview` — `--stability.level=experimental` ist damit die engste
  ausreichende Stufe, keine unnötige Absenkung.
  Der `emptyDir` für `--storage.path` (`workload.yaml`, Volume `tmp`) trägt
  `sizeLimit: 1Gi` — dimensioniert auf das schlechteste gemessene
  6-Stunden-Fenster (297 MiB, siehe dort). `validate.sh` prüft nur
  Kubernetes-Schema, nicht Alloy-Syntax; die Prüfmethode oben ist deshalb vor
  jeder Änderung an `config.alloy` von Hand zu wiederholen.

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

Vor jeder Änderung an `config.alloy`: gegen die im Cluster laufende Version
prüfen, **ohne** etwas anzuwenden — `validate.sh` prüft nur Kubernetes-Schema.

```bash
POD=$(kubectl -n app-alloy get pod -l app.kubernetes.io/name=alloy -o name)
# config.alloy liegt eingebettet in der ConfigMap -- ueber jsonpath extrahieren,
# nicht von Hand aus der YAML kopieren (Einrueckung).
kubectl -n app-alloy get configmap alloy-config -o jsonpath='{.data.config\.alloy}' \
  | kubectl -n app-alloy exec -i "$POD" -c alloy -- sh -c 'cat > /tmp/check.alloy'
kubectl -n app-alloy exec "$POD" -c alloy -- alloy validate --stability.level=experimental /tmp/check.alloy
kubectl -n app-alloy exec "$POD" -c alloy -- alloy fmt -t /tmp/check.alloy   # nur Stilhinweis, kein Fehler
kubectl -n app-alloy exec "$POD" -c alloy -- rm -f /tmp/check.alloy
```

`/tmp` ist der `emptyDir`-Mount des Pods selbst — das schreibt nichts in die
ConfigMap und ändert am Cluster nichts. Für eine noch nicht angewendete
Änderung an `configmap.yaml`: die erste Zeile durch `yq '.data."config.alloy"'
apps/alloy/configmap.yaml` ersetzen.

Im lokalen Cluster muss danach `count by(cluster, job)(up)` neben
`cluster="local"` auch `cluster="public"` mit den Jobs `kubelet` und
`kube-state-metrics` liefern, und Loki muss unter `cluster="public"` die
Public-Namespaces kennen.
