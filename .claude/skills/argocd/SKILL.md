---
name: argocd
description: Argo-CD-Applikationen im Public-Cluster-Repository hinzufügen, synchronisieren und diagnostizieren.
---

# Public Argo CD

- Argo CD wird von `public-cluster-nix` gebootstrapt; dieses Repository
  enthält nur Applikationsressourcen unterhalb von `apps/`.
- Jede `apps/<name>/argocd.yaml` wird vom Nix-verwalteten
  `public-apps`-ApplicationSet entdeckt, das eine nach dem Verzeichnis
  benannte Application (`authentik`, `netbird`, …) erzeugt und den flachen
  Pfad `apps/<name>` synchronisiert. Es gibt keine `base/`- oder
  `overlays/`-Verzeichnisse; es gibt nur eine Umgebung.
- Das ApplicationSet synchronisiert vom `release`-Branch. `selfHeal` ist an,
  Auto-Prune ist aus, ein aus Git entferntes Objekt wird also live nicht
  gelöscht.
- Das `public-apps`-AppProject verwenden. Applikations-Namespaces sind
  `app-*`; eine App kann den Ziel-Namespace über `namespace:` in ihrer
  `argocd.yaml` überschreiben (`mail-edge` nutzt `app-mailedge`).
- Drift in Git korrigieren. Ein Refresh ist unbedenklich; Sync/Prune ist ein
  Schreibvorgang und muss von Health-, Event- und Log-Prüfungen gefolgt
  werden.
- Der Repository-Zugriff nutzt einen read-only SSH-Deploy-Key (in
  `public-cluster-nix` aus Vault registriert).
- Niemals Kubernetes-Secret-Daten oder Argo-CD-Zugangsdaten ausgeben.
