# valkey

Shared in-memory cache (Valkey, the OSS Redis fork) for the **public** cluster —
a standalone app so multiple apps can use one instance, mirroring the local
cluster's [`app-valkey`](../../../local-cluster-kubernetes/apps/valkey/).

| | |
| --- | --- |
| Namespace | `app-valkey` |
| Service | `valkey.app-valkey.svc.cluster.local:6379` |
| Image | `valkey/valkey:9.1-alpine` (non-root uid 999, read-only root fs) |
| Persistence | none — `emptyDir`, in-memory only (`--save ""`, `--appendonly no`) |
| Eviction | `noeviction` (never silently drop keys with TTLs) |
| Access | no password; restricted by CiliumNetworkPolicy to consumer namespaces |

## Consumers

Grant a namespace access by adding it to `allow-app-ingress` in
[`base/networkpolicy.yaml`](base/networkpolicy.yaml) and pointing the app at
`valkey.app-valkey.svc.cluster.local`. Current consumers:

- **authentik** (`app-authentik`) — `AUTHENTIK_REDIS__HOST`
