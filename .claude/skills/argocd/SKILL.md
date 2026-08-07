---
name: argocd
description: Add, sync and diagnose Argo CD applications in the public cluster repository.
---

# Public Argo CD

- Argo CD is bootstrapped by `public-cluster-nix`; this repository contains
  only application resources below `apps/`.
- Each `apps/<name>/argocd.yaml` is discovered by the Nix-managed `public-apps`
  ApplicationSet, which creates an Application named after the directory
  (`authentik`, `netbird`, …) and syncs the flat path `apps/<name>`. There are
  no `base/` or `overlays/` directories; production is the only environment.
- The ApplicationSet syncs from the `release` branch. `selfHeal` is on,
  auto-prune is off, so removing a resource from Git does not delete it live.
- Use the `public-apps` AppProject. Application namespaces are `app-*`; an app
  may override the target namespace via `namespace:` in its `argocd.yaml`
  (`mail-edge` uses `app-mailedge`).
- Correct drift in Git. A refresh is safe; sync/prune is a write operation and
  must be followed by health, event and log checks.
- Repository access uses a read-only SSH deploy key (registered in
  `public-cluster-nix` from Vault).
- Never output Kubernetes Secret data or Argo CD credentials.
