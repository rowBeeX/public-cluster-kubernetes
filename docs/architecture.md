# Public application architecture

Cloudflare round-robin DNS sends `*.dev0.sedware.net` traffic to both public
nodes. HAProxy terminates TLS, applies short-lived static-object caching and
forwards HTTP to the host-network Traefik DaemonSet. Traefik routes to services
declared in this repository.

The control plane is intentionally not highly available:
`public-cluster-host-1` is the only k3s server and
`public-cluster-host-2` is an agent. Both remain ingress/workload nodes.

`public-shared-bulk` is backed by the standalone NFS simulator in Dev and by a
Hetzner StorageBox in Production. Stateful control-plane data such as NetBird's
SQLite database and Authentik PostgreSQL stays on Host 1's local SSD because
the cluster has no database HA design. Authentik media uses shared NFS.

Secrets are created at runtime by `public-cluster-nix` from SOPS sources before
the ApplicationSet is enabled. No cleartext application secret belongs here.
