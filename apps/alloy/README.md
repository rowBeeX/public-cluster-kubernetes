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
  und steht nicht in `gates/exceptions.md`.
- **Multi-Arch-Digest.** Host 2 ist aarch64; der Alloy-Digest ist der
  Index-Digest, nicht der amd64-Child-Digest aus `local-cluster-kubernetes`.
- **Serienbudget.** Vor `prometheus.remote_write` steht eine `keep`-Liste
  (`prometheus.relabel "budget"`). Der empfangende Prometheus lief auf einem
  Node mit 30 GiB RAM bei ~332 000 Serien und startete deswegen alle 31 Minuten
  neu. Zusätzlich beschränkt `--resources=…` kube-state-metrics an der Quelle
  (kein leases/endpointslices/configmaps/secrets), und eine zweite Regel wirft
  cAdvisor-Serien ohne `pod`-Label weg (Host-Cgroups; Host-Metriken kommen vom
  node_exporter des NixOS-Dienstes).
- **Eine kube-state-metrics-Ressource braucht drei Stellen.** `--resources=`
  in `workload.yaml`, das Leserecht in `rbac.yaml` und die `keep`-Regel in
  `configmap.yaml`. Fehlt eine, ist der Effekt null, aber das Symptom
  unterschiedlich: ohne Leserecht bleibt der Scrape-Endpunkt still und nur
  kube-state-metrics protokolliert (`reflector.go … is forbidden`), ohne
  `keep`-Regel steht die Serie lokal und kommt trotzdem nicht im zentralen
  Prometheus an. Genau daran hing `cronjobs` bis zum 2026-08-22: `--resources`
  und `keep`-Regel standen, das Recht fehlte, und
  `sedware-vault-snapshot-missing-public` war wegen
  `noDataState: Alerting` dauerhaft rot.
- **Stream-Labels identisch zum lokalen Cluster.** Die acht
  `discovery.relabel "pods"`-Regeln sind zeichengleich aus
  `local-cluster-kubernetes/apps/alloy/values.yaml` übernommen. Abweichende
  Labels brechen clusterübergreifende Grafana-Queries lautlos. Am 2026-08-22 an
  Loki gegengeprüft, nicht am Diff: ein Stream aus `cluster="public"` und einer
  aus `cluster="local"` tragen denselben Satz
  `app, component, container, namespace, node_name, pod, job, cluster`. Der Node
  heißt in Logstreams `node_name`, in Metrikreihen `node` — beides bewusst, weil
  beide Cluster es so halten.
- **cert-manager wird seit 2026-08-12 mitgescrapt.** Davor kannte der zentrale
  Prometheus `certmanager_`-Serien nur mit `cluster="local"` — ein
  abgelaufenes oder hängendes Edge-Zertifikat dieses Clusters hätte also
  keinen Alarm ausgelöst, obwohl der Exporter auf `:9402` längst lief (104
  Serien gemessen).
- **WAL-Puffer für Loki.** `loki.write "central"` ohne `wal`-Block hält
  Zeilen nur im Speicher und wirft sie nach erschöpften Wiederholungen
  endgültig weg — gemessen 2026-08-19 bis 2026-08-21 fehlten deshalb 26 von 73
  Stundenfenstern vollständig in Loki. Der lokale Alloy braucht den Block
  nicht — er schreibt clusterintern, ohne den NetBird-Hop.

  Der `emptyDir` für `--storage.path` (`workload.yaml`, Volume `tmp`) trägt
  `sizeLimit: 1Gi`, dimensioniert auf das schlechteste gemessene
  6-Stunden-Fenster. Unabhängig nachgemessen am 2026-08-22 über sieben Tage
  (`sum(bytes_over_time({cluster="public"}[6h]))`, Schritt 1 h): Maximum
  311 924 792 Byte = **297 MiB**. `1Gi` hält dagegen das 3,4-fache vor.

- **`--stability.level=experimental` ist nicht nötig, bleibt aber gesetzt.**
  Die Referenzdoku (`docs/.../loki.write.md`, Tag v1.18.1) markiert den
  `wal`-Block als experimentelles Feature. Das **Binary** derselben Version
  setzt das nicht durch: `loki.write` ist als
  `featuregate.StabilityGenerallyAvailable` registriert, und die einzige
  Stability-Prüfung in der Komponente (`validateConfigStabilityLevel`) betrifft
  ausschließlich `queue_config` — nicht `wal`. Alle acht hier verwendeten
  Komponenten sind GA.

  Nachgemessen mit dem gepinnten Image, ohne Flag: `alloy run` legt
  `<storage.path>/loki.write.central/wal/remote` an und meldet keinen
  Stability-Fehler. Gegenprobe, dass das Gate überhaupt scharf ist:
  `--feature.prometheus.direct-fanout.enabled` wird auf derselben Stufe mit
  „can only be used at experimental stability level" abgewiesen.

  Die Stufe bleibt trotzdem stehen. Setzt eine künftige Alloy-Version das
  Doku-Label doch durch, würde der `wal`-Block abgewiesen und Alloy startete
  gar nicht mehr — das nimmt genau die Telemetrie mit, die der Block schützt.
  Die Kosten der Absenkung sind dagegen null, solange keine Komponente
  experimentelle Syntax verwendet.

- **Ein kalter Alloy-Pod verliert Logzeilen von VOR seinem Start nicht.** Eine
  frühere Fassung dieser Doku behauptete das Gegenteil (`SinceTime` auf
  `time.Now()`) — falsch gelesen. Nachgeprüft am gepinnten Tag `v1.18.1`, drei
  Quelldateien: `kubernetes.go` (`getTailerOptions`) setzt
  `kubetail.Options.TailFromEnd` nirgends, Go-Zeitwert also `false`; in
  `kubetail/tailer.go` bleibt `offsetTime` deshalb `nil`, wenn keine
  Leseposition existiert (der `TailFromEnd`-Zweig in `tail()` greift nur bei
  `true`); ein `nil`-`SinceTime` liefert die Kubernetes-Log-API das komplette
  am Node vorgehaltene Log, genau wie `kubectl logs <pod>` ohne `--since`. Ein
  Container, der vor dem Alloy-Pod hochkommt, wird also vollständig
  nachgelesen, sobald `discovery.kubernetes` ihn findet — auch nach Rollout,
  Eviction oder Node-Reboot des Alloy-Pods selbst.

  Die tatsächliche Grenze ist die Log-Rotation des Nodes (containerd, wenige
  MB je Container): Steht der Alloy-Pod länger unten, als die Rotation
  braucht, um die ältesten Zeilen zu verwerfen, sind genau die weg —
  unabhängig von Alloys eigener Leseposition. `loki.source.kubernetes` merkt
  sich seine Position trotzdem in
  `<storage.path>/loki.source.kubernetes.pods/positions.yml` (`emptyDir`), um
  bei einem bloßen Container-Neustart im bestehenden Pod nicht doppelt zu
  lesen; ein Neuentstehen des **Pods** verwirft die Positionen und fängt beim
  vollen, noch vorhandenen Node-Log neu an. Das Host-Journal
  (`job="systemd-journal"`) bleibt trotzdem die richtige Quelle für einen
  Node-Absturz: sein eigener Alloy-Dienst läuft unabhängig von diesem Pod.

  `validate.sh` prüft nur Kubernetes-Schema, nicht Alloy-Syntax; die
  Prüfmethode unten ist deshalb vor jeder Änderung an `config.alloy` von Hand
  zu wiederholen.

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
kubectl -n app-alloy exec "$POD" -c alloy -- alloy validate /tmp/check.alloy   # ohne Flag: muss ebenso durchlaufen
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
