---
name: argocd
description: Add, sync and diagnose Argo CD applications in the public cluster repository.
---

# Public Argo CD

- Argo CD is bootstrapped by `public-cluster-nix`; this repository contains
  only application resources below `apps/`.
- Each `apps/<name>/argocd.yaml` is discovered by the Nix-managed
  ApplicationSet and renders `apps/<name>/overlays/<environment>`.
- Use the `public-apps` AppProject. Application namespaces are `app-*`.
- Correct drift in Git. A refresh is safe; sync/prune is a write operation and
  must be followed by health, event and log checks.
- Repository access uses a read-only SSH deploy key (registered in
  `public-cluster-nix` from Vault).
- Never output Kubernetes Secret data or Argo CD credentials.
