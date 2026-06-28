# Repo-Struktur

Kubernetes-Manifeste für den öffentlichen Cluster (Authentik, NetBird, AdGuard).
ArgoCD im Public-Cluster deployed diese Apps via GitOps.
Kein Ingress-Controller — HAProxy terminiert TLS direkt auf NodePort.

## Dateibaum

```
README.md                       Kurzübersicht: Zweck, Apps, Traffic-Fluss
.gitignore                      Schließt lokale Secrets und Nix-Ergebnisse aus

apps/
  adguard-home/                 AdGuard Home DNS (NodePort 30300)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Service, PVC, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-spezifische Überschreibungen: Image-Tag, Ressourcen

  authentik/                    Authentik SSO / OIDC-Provider (NodePort 30900)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Service, PVC, Secret-Refs, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-spezifische Überschreibungen: Image-Tag, Ressourcen

  netbird/                      NetBird VPN (Dashboard NodePort 30810, Signal/Relay NodePort 30811)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Services, PVC, ConfigMap, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-spezifische Überschreibungen: Image-Tag, Ressourcen

docs/
  architecture.md               Systemüberblick: Traffic-Fluss, HAProxy→NodePort→Pod, TLS-Terminierung
  structure.md                  Diese Datei
```

## Apps-Übersicht

| App | Dienst | NodePort |
|-----|--------|----------|
| `authentik` | Authentik SSO / OIDC-Provider | 30900 |
| `netbird` | NetBird Dashboard + Control | 30810 / 30811 |
| `adguard-home` | AdGuard Home DNS | 30300 |

Vault wird direkt über k3s-Helm-Manifeste in `public-cluster-nix` deployed, nicht über ArgoCD.

## Traffic-Fluss

```
Internet → HAProxy :443 (TLS-Terminierung) → NodePort → Kubernetes-Pod
```

## Tests und Validierung

Tests und Kustomize-Validierung befinden sich in `cluster-testing/public-cluster/kubernetes/`.
