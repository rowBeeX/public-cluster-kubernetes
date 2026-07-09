# App-Manifest-Layout (#37)

Einheitliches Layout für kustomize-native Apps, damit Review-Diffs klein bleiben
und Ressourcen logisch getrennt sind. Statt eines Monolithen (`resources.yaml`
mit Namespace, Workload, Policies …) trägt jede App im `base/`:

| Datei | Inhalt |
|-------|--------|
| `namespace.yaml` | `Namespace`, `LimitRange`, `ResourceQuota` — das Namespace-Gerüst |
| `workload.yaml` | `Deployment`/`StatefulSet`, `Service`, `PVC`, `Certificate`, `ConfigMap`, Jobs, `Vault*` … — die App selbst und ihr Umfeld |
| `networkpolicy.yaml` | alle `CiliumNetworkPolicy` (default-deny + allow-Regeln) |

Sehr große Apps dürfen feiner splitten (z. B. eine Datei je
`CiliumNetworkPolicy`, wie `apps/stalwart` im local-cluster). Das Minimum ist die
Dreiteilung oben.

`base/kustomization.yaml` listet die Dateien in der Reihenfolge
`namespace.yaml → workload.yaml → networkpolicy.yaml`.

## Durchgesetzt

`cluster-testing` `validate.sh` (Bereich `kubernetes`) verweigert eine
Manifest-Datei, die einen `Namespace` **und** ein Workload/eine Policy in einer
Datei mischt — so entsteht kein neuer Monolith.
