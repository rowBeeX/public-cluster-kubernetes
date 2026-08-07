# valkey

Gemeinsam genutzter In-Memory-Cache (Valkey, der OSS-Redis-Fork) für den
**public** Cluster — eine eigenständige App, damit mehrere Apps eine Instanz
nutzen können, analog zum [`app-valkey`](../../../local-cluster-kubernetes/apps/valkey/)
des lokalen Clusters.

| | |
| --- | --- |
| Namespace | `app-valkey` |
| Service | `valkey.app-valkey.svc.cluster.local:6379` |
| Image | `valkey/valkey:9.1-alpine` (non-root UID 999, read-only Root-FS) |
| Persistenz | keine — `emptyDir`, nur In-Memory (`--save ""`, `--appendonly no`) |
| Eviction | `noeviction` (verwirft nie still Keys mit TTLs) |
| Zugriff | kein Passwort; per CiliumNetworkPolicy auf Consumer-Namespaces begrenzt |

## Consumer

Zugriff für einen Namespace wird durch Ergänzen in `allow-app-ingress` in
[`networkpolicy.yaml`](networkpolicy.yaml) gewährt; die App zeigt dann auf
`valkey.app-valkey.svc.cluster.local`. Aktuelle Consumer:

- **authentik** (`app-authentik`) — `AUTHENTIK_REDIS__HOST`
