# Repo-Struktur

Kubernetes-Manifeste für den öffentlichen Cluster (Authentik, NetBird, AdGuard).
ArgoCD im Public-Cluster deployed diese Apps via GitOps.
Kein Ingress-Controller — HAProxy terminiert TLS direkt auf NodePort.

Die eigentlichen NodePort-Services (Typ `NodePort`) sind in
`public-cluster-nix/modules/kubernetes/manifests/platform/nodeports/services.yaml` definiert.
Die Services in `resources.yaml` hier verwenden `type: ClusterIP`.

## Dateibaum

```
README.md                       Kurzübersicht: Zweck, Apps, Traffic-Fluss
.gitignore                      Schließt lokale Secrets und Nix-Ergebnisse aus

apps/
  adguard-home/                 AdGuard Home DNS (erreichbar via NodePort 30300, definiert in public-cluster-nix)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Service (ClusterIP), PVC, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-Overlay (referenziert nur Base; aktuell keine Patches)

  authentik/                    Authentik SSO / OIDC-Provider (erreichbar via NodePort 30900, definiert in public-cluster-nix)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Service (ClusterIP), PVC, Secret-Refs, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-Overlay (referenziert nur Base; aktuell keine Patches)

  netbird/                      NetBird VPN (erreichbar via NodePort 30810/30811, definiert in public-cluster-nix)
    argocd.yaml                 ArgoCD Application-Manifest: Sync-Policy, Namespace, Source
    base/
      kustomization.yaml        Kustomize-Basis-Ressourcenliste
      resources.yaml            Kubernetes-Ressourcen: Namespace, Deployment, Services (ClusterIP), PVC, Secrets, NetworkPolicies
    overlays/
      dev/
        kustomization.yaml      Dev-Overlay: Image-Tag, Ressourcen

docs/
  architecture.md               Systemüberblick: Traffic-Fluss, HAProxy→NodePort→Pod, TLS-Terminierung
  structure.md                  Diese Datei
```

## Apps-Übersicht

| App | Dienst | NodePort (in public-cluster-nix definiert) |
|-----|--------|--------------------------------------------|
| `authentik` | Authentik SSO / OIDC-Provider | 30900 |
| `netbird` | NetBird Dashboard + Control | 30810 / 30811 |
| `adguard-home` | AdGuard Home DNS | 30300 |

Vault wird direkt über k3s-Helm-Manifeste in `public-cluster-nix` deployed, nicht über ArgoCD.

## Traffic-Fluss

```
Internet → HAProxy :443 (TLS-Terminierung) → NodePort → Kubernetes-Pod
```

## Tests und Validierung

Tests und Kustomize-Validierung befinden sich in `../cluster-testing/public-cluster/kubernetes/`
(erfordert den Workspace-Kontext mit beiden Repos nebeneinander).
