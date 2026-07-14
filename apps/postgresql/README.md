# postgresql

Central CloudNativePG (CNPG) PostgreSQL cluster for the **public** cluster,
backing Authentik. A vanilla `cloudnative-pg/postgresql` image serving a single
database — unlike the local cluster's multi-database
[`app-postgresql`](../../../local-cluster-kubernetes/apps/postgresql/) (vectorchord).

| | |
| --- | --- |
| Namespace | `app-postgresql` |
| CNPG Cluster | `postgres` (1 instance) |
| Service | `postgres-rw.app-postgresql.svc.cluster.local:5432` |
| Image | `ghcr.io/cloudnative-pg/postgresql:18` (digest-pinned) |
| Storage | `10Gi` on `public-primary-super-fast` (node-local SSD) |
| Backup | Barman Cloud plugin → S3 `ObjectStore` `postgres-backup` |
| Credentials | per-consumer roles via Vault self-service (`VaultStaticSecret`) |

## Consumers

Each consumer gets its own database and role, provisioned through Vault plus a
seed `Job` (no shared superuser). Current consumers:

- **authentik** (`app-authentik`) — database `authentik`
