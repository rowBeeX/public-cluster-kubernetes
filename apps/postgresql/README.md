# postgresql

Zentraler CloudNativePG-(CNPG-)PostgreSQL-Cluster für den **public** Cluster,
Backend für Authentik. Ein unverändertes `cloudnative-pg/postgresql`-Image,
das eine einzelne Datenbank bedient — anders als das Multi-Datenbank-
[`app-postgresql`](../../../local-cluster-kubernetes/apps/postgresql/)
(vectorchord) des lokalen Clusters.

| | |
| --- | --- |
| Namespace | `app-postgresql` |
| CNPG-Cluster | `postgres` (1 Instanz) |
| Service | `postgres-rw.app-postgresql.svc.cluster.local:5432` |
| Image | `ghcr.io/cloudnative-pg/postgresql:18` (digest-gepinnt) |
| Storage | `10Gi` auf `public-primary-super-fast` (node-lokale SSD) |
| Backup | Barman-Cloud-Plugin → S3-`ObjectStore` `postgres-backup` |
| Zugangsdaten | Rollen je Consumer via Vault-Self-Service (`VaultStaticSecret`) |

## Consumer

Jeder Consumer bekommt seine eigene Datenbank und Rolle, provisioniert über
Vault plus einen Seed-`Job` (kein gemeinsamer Superuser). Aktuelle Consumer:

- **authentik** (`app-authentik`) — Datenbank `authentik`

## Kein VPA für den CNPG-`Cluster`

Alle übrigen Apps dieses Repos tragen einen `VerticalPodAutoscaler` mit
`updateMode: Off`. Hier fehlt er bewusst: der `Cluster`-CR ist kein
Deployment/StatefulSet mit `scale`-Subresource, sondern eine
Operator-verwaltete Custom Resource — ein VPA-`targetRef` darauf liefert keine
Empfehlung. Rightsizing des Instanz-Pods bleibt manuell über
`spec.resources.requests` in `workload.yaml`.

## Monitoring: warum die Standardabfragen an sind

Nur `disableDefaultQueries: false` liefert die `pg_stat_archiver`-Sicht, die
einzige Quelle für „steht die WAL-Archivierung". Bis 2026-08-10 liefen weder
diese Abfragen noch die CNPG-Instanzmetriken (Exporter im Instance-Manager auf
`:9187`) aus dem Cluster hinaus — Alloy holte sie schlicht nicht ab. Die
Nachtsicherung scheiterte an diesem Tag, ohne dass irgendwo ein Alarm entstand;
die Archivierung stand zuvor bereits 48 h still, unbemerkt. Kosten: ein paar
Dutzend zusätzliche `SELECT`s auf `pg_stat_*` je Scrape, und von den 37
`cnpg_`-Metriken lässt der Alloy-Serienbudget-Filter (`apps/alloy/configmap.yaml`)
genau zwei aus dem Cluster heraus.
