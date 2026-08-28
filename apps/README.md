# Apps — Public Cluster

Kubernetes-Manifeste für die öffentlichen Cluster-Apps. Deployment erfolgt
über ArgoCD (ApplicationSet aus `public-cluster-nix`).

Die App-Liste ist `ls apps/` — jede App trägt Zweck, Namespace und
Besonderheiten in ihrer eigenen `README.md`. Eine zweite, handgepflegte Liste
hier würde bei der ersten neuen App veralten.

Jede PSA-Stufe außer `restricted` ist eine begründete Ausnahme und in
[`gates/exceptions.md`](../gates/exceptions.md) geführt;
`<Monorepo>/public-cluster-kubernetes/validate.sh` erzwingt das.

## Konventionen

- Ressourcen je App aufgeteilt direkt im App-Verzeichnis (`namespace.yaml` → `workload.yaml` → `networkpolicy.yaml`); eine Datei, die einen `Namespace` **und** einen Workload/eine Policy mischt, lehnt `validate.sh` ab
- Es gibt nur eine Umgebung, deshalb keine `base/`- oder `overlays/`-Ebene:
  ArgoCD synchronisiert `apps/<name>` direkt.
- HTTP wird ausschließlich per `HTTPRoute` an das Envoy-Gateway (`public`
  in `gateway-system`) gebunden.
- SMTP und STUN nutzen explizite Cilium Node IPAM Services auf den
  Gateway-Node-Adressen; deren LoadBalancer-NodePorts sind deaktiviert.
- Secrets stehen nie in diesem Repo: sie kommen aus Vault über den Vault
  Secrets Operator (`VaultAuth`/`VaultStaticSecret`) oder aus dem
  SOPS-gestützten Bootstrap in `public-cluster-nix`
