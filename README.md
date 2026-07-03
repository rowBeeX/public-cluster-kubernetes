# Public Cluster Kubernetes

Argo CD application source for the Sedware public k3s cluster. The Cilium
dataplane, Gateway API, cert-manager, CrowdSec and Argo CD itself are
managed by the sibling `public-cluster-nix` repository.

Applications currently managed here:

- `authentik`: public identity provider with PostgreSQL and Valkey;
- `netbird`: self-hosted control plane and dashboard;
- `adguard-home`: NetBird-only DNS and administration UI;
- `mail-edge`: Mail Edge / MX relay (SMTP :25) fronting the Local Stalwart backend;
- `public-nginx`: public nginx test server on the Envoy edge;
- `local-nginx-proxy`: public edge entry that re-encrypts to the local cluster's
  nginx over NetBird;
- `smoke`: stateless whoami smoke-test app that exercises the public Envoy edge
  end-to-end (not a user-facing service).

WordPress is intentionally not deployed yet. Future public applications can use
the RWX StorageClass `public-shared-bulk`; database workloads should continue to
use node-local SSD storage unless an application-specific HA database design is
introduced.

## Validation

```bash
bash cluster-testing/public-cluster/kubernetes/validate.sh
```

The script renders every dev overlay and validates YAML/Kustomize structure.
Live validation is performed through Argo CD and `sudo k3s kubectl` on
`public-cluster-host-1`.
