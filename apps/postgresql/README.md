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
