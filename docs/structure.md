# Repo-Struktur

Kubernetes-Manifeste für den öffentlichen Cluster (Authentik, NetBird, AdGuard, Vault).

## Ordner

| Pfad | Inhalt |
|------|--------|
| `apps/` | Kubernetes-Anwendungen als Kustomize-Overlays (base + dev-Overlay) |
| `apps/<app>/base/` | Basis-Ressourcen der Anwendung (HelmRelease, ConfigMap, …) |
| `apps/<app>/overlays/dev/` | Dev-spezifische Überschreibungen |
| `docs/` | Dokumentation zur Repo-Struktur |

## Wichtige Dateien

| Datei | Inhalt |
|-------|--------|
| `apps/<app>/argocd.yaml` | ArgoCD Application-Manifest |
| `apps/<app>/base/kustomization.yaml` | Kustomize-Basis-Ressourcenliste |

## Apps-Übersicht

| App | Dienst | NodePort |
|-----|--------|----------|
| `authentik` | Authentik SSO | 30900 |
| `netbird` | NetBird Dashboard + Control | 30810 / 30811 |
| `adguard-home` | AdGuard DNS | 30300 |
| `vault` | HashiCorp Vault | 30820 |

Der Traffic-Fluss: `HAProxy :443 → NodePort → Pod`.
Keine Ingress-Controller — HAProxy terminiert TLS direkt auf NodePort.

## Tests und Validierung

Tests und Kustomize-Validierung befinden sich in `cluster-testing/public-cluster/kubernetes/`.
