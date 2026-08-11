---
name: argocd
description: Argo-CD-Applikationen dieses Repos hinzufügen, synchronisieren und diagnostizieren. Verwenden beim Onboarding einer App, wenn ein Commit nicht im Cluster ankommt, und bei OutOfSync-, Degraded- oder Renderfehlern.
---

# Public Argo CD

- Argo CD wird von `public-cluster-nix` gebootstrapt; dieses Repository
  enthält nur Applikationsressourcen unterhalb von `apps/`.
- Jede `apps/<name>/argocd.yaml` wird vom Nix-verwalteten
  `public-apps`-ApplicationSet entdeckt, das eine nach dem Verzeichnis
  benannte Application (`authentik`, `netbird`, …) erzeugt und den flachen
  Pfad `apps/<name>` synchronisiert. Es gibt keine `base/`- oder
  `overlays/`-Verzeichnisse; es gibt nur eine Umgebung.
- Das ApplicationSet synchronisiert vom **`release`**-Branch. Ein Push nach
  `main` allein ändert am Cluster nichts — nötig sind beide Refs
  (`git push origin main` **und** `git push origin main:release`), siehe
  `../docs/05-deploy.md`.
- `selfHeal: true` **und `prune: true`**: was aus dem Render verschwindet, wird
  live gelöscht. Vor jedem Umbau, der Objekte verschiebt,
  `kubectl kustomize apps/<name>` vorher und nachher zählen.
- Ein hängender Sync, der auf `healthy` wartet, blockiert die Anwendung des
  *nächsten* Commits. Ist genau der der Fix, hilft nur
  `kubectl -n argocd patch app <name> --type=merge -p
  '{"status":{"operationState":{"phase":"Terminating"}}}'`.
- Das `public-apps`-AppProject verwenden. Applikations-Namespaces sind
  `app-*`; eine App kann den Ziel-Namespace über `namespace:` in ihrer
  `argocd.yaml` überschreiben (`mail-edge` nutzt `app-mailedge`).
- Drift in Git korrigieren. Ein Refresh ist unbedenklich; Sync/Prune ist ein
  Schreibvorgang und muss von Health-, Event- und Log-Prüfungen gefolgt
  werden.
- Der Repository-Zugriff nutzt einen read-only SSH-Deploy-Key (in
  `public-cluster-nix` aus Vault registriert).
- Niemals Kubernetes-Secret-Daten oder Argo-CD-Zugangsdaten ausgeben.
