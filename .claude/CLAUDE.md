# CLAUDE.md

Diese Datei gibt Claude Code Hinweise für die Arbeit in diesem Repository.

Was mehr als ein Repository betrifft, steht in `../docs/` und wird hier nicht
wiederholt — `../CLAUDE.md` nennt die Regeln, `../../docs/10-repo-wegweiser.md`
beantwortet „ich will X ändern, wo?", `../../docs/05-deploy.md` beschreibt, wie
eine Änderung live geht.

Skills hier: `argocd` und `kubernetes`. Plattform und Edge liegen in
`public-cluster-nix`, die bestandsweiten Skills (Logs, CrowdSec, DNS,
GitHub-Auth) in `local-cluster-nix/.claude/skills/`.

## Zweck

ArgoCD-App-Repository für den **öffentlichen** Sedware-Cluster — den einzigen
Internet-Edge der Infrastruktur. Die Plattformschicht (k3s, Cilium, Envoy
Gateway, cert-manager, CrowdSec, Vault, ArgoCD selbst) liegt in
`public-cluster-nix`; dieses Repo besitzt alles darüber.

Weil hier alles am offenen Internet hängt, ist dieses Repo das strengere der
beiden App-Repos: `restricted` ist der Default, jede Abweichung braucht einen
Eintrag in `docs/exceptions.md`, und `validate.sh` erzwingt das.

## Kustomize, kein Helm

Das `public-apps`-ApplicationSet in `public-cluster-nix` kennt ausschließlich
`path` und rendert mit `kubectl kustomize`. **Es gibt keine Helm-Quelle.** Eine
App, die upstream nur als Chart existiert, wird hier von Hand als Manifest
geschrieben (siehe `apps/gitlab-runner/README.md`). Images sind direkt im
Manifest gepinnt, als `tag@sha256:<index-digest>`.

Host 2 ist aarch64: der Digest MUSS der Multi-Arch-Index sein, nie ein
arch-spezifischer Child.

## Repository-Aufbau

```
apps/
  README.md             die einzige App-Liste des Repos (Namespace, PSA, Zweck)
  <app>/
    argocd.yaml         ApplicationSet-Deskriptor (sourceType, optional namespace:)
    README.md           Pflicht je App
    kustomization.yaml  listet namespace.yaml -> workload.yaml -> networkpolicy.yaml
    namespace.yaml      Namespace, LimitRange, ResourceQuota
    workload.yaml       Workloads, Services, Routes, PVCs, Certificates, Vault*
    networkpolicy.yaml  CiliumNetworkPolicies (Default-Deny + Allow)
docs/
  app-layout.md         die Dreiteilung oben, samt Durchsetzung
  architecture.md       nur die Applikationsschicht; Plattform/Edge in public-cluster-nix
  exceptions.md         jede PSA-/Härtungs-Abweichung mit Owner, Risiko, Review-Datum
  structure.md
```

Es gibt kein `base/` und kein `overlays/`: es gibt genau eine Umgebung.
Regeln zum Layout stehen in `docs/app-layout.md` — eine Datei, die einen
`Namespace` **und** ein Workload/eine Policy enthält, lehnt `validate.sh` ab.

## Kubernetes-Konventionen

- **Nur `resources.requests`, keine `limits`.** `validate.sh` prüft das für
  jedes Deployment/StatefulSet/DaemonSet.
- **Pod Security: `restricted` ist der Default.** Ein Namespace mit
  `enforce != restricted` muss in `docs/exceptions.md` stehen, sonst schlägt
  `validate.sh` fehl. Beim Ändern einer Ausnahme immer prüfen, ob die
  *Begründung* noch stimmt, nicht nur der Eintrag.
- Namespace: jede App bekommt ihren eigenen `app-<name>`-Namespace, mit dem
  vollständigen Pod-Security-Triple (`enforce`/`audit`/`warn` je mit
  `-version`) und den Labels `core.sedware.net/owner` (team-/rollenbasiert,
  nie persönlich), `core.sedware.net/purpose`, `app.kubernetes.io/part-of`.
- CiliumNetworkPolicy statt k8s-`NetworkPolicy`: Default-Deny plus explizite
  Allow-Regeln. Ein leeres `ingress: []` verwirft Cilium — die gültige
  Default-Deny-Form selektiert eine leere Endpoint-Menge.
- `Ingress`, `NetworkPolicy`, Traefik-Ressourcen und HTTP-NodePorts sind
  verboten.
- HTTP/gRPC/WebSocket ausschließlich per `HTTPRoute`/`GRPCRoute` am Gateway
  `public` in `gateway-system`. Raw TCP/UDP (SMTP `:25`, STUN `:3478`) über
  explizite Cilium-Node-IPAM-`LoadBalancer`-Services
  (`loadBalancerClass: io.cilium/node`, NodePorts aus); `spec.externalIPs` ist
  verboten.
- Secrets stehen nie im Repo: `VaultAuth`/`VaultStaticSecret` über den Vault
  Secrets Operator, oder der SOPS-Bootstrap in `public-cluster-nix`.

## Site und Zugriff

Genau eine Umgebung, alle öffentlichen Hostnamen unter `sedware.net`.

Zwei Nodes, eine Control-Plane — bewusst nicht HA:

| Node | Arch | Rolle |
|------|------|-------|
| `public-cluster-host-1` | amd64 | Control-Plane, Gateway-Node, hält die node-lokalen Volumes |
| `public-cluster-host-2` | aarch64 | Agent, Gateway-Node |

`kubectl` läuft **ausschließlich** über `public-cluster-host-1` mit
`sudo k3s kubectl`; nie einen lokalen Kontext benutzen. Node-Auswahl im
Manifest: `public.sedware.net/control-plane: "true"` für Host 1,
`gateway.sedware.net/enabled: "true"` für beide Gateway-Nodes.

StorageClasses: `public-primary-super-fast` (node-lokal, Host 1, Reclaim
`Retain`) für Zustand, `public-shared-bulk` (SMB CSI gegen eine Hetzner
StorageBox, RWX) für gemeinsame Bulk-Daten.

Das ApplicationSet synchronisiert vom `release`-Branch, mit `selfHeal: true`
**und `prune: true`** — ein aus dem Render verschwundenes Objekt wird live
gelöscht. Ein Push nach `main` allein deployt nichts; nötig sind beide Refs
(`../../docs/05-deploy.md`).

## Validieren

```bash
bash cluster-testing/public-cluster/kubernetes/validate.sh   # muss 0 liefern
yamllint -f parsable .
kubectl kustomize apps/<name>
```

`validate.sh` rendert jede App und prüft danach unter anderem: Image-Digests,
kubeconform-Schema, conftest-Security-Policies, ServiceAccount-Tokens, das
App-Layout, den Cluster-Vertrag (Labels, keine Limits), die PSA-Ausnahmen, den
Node-IPAM-Service-Vertrag und das Anti-Open-Relay-Gate für `POSTFIX_mynetworks`.

Live-Validierung danach auf Host 1: Nodes, Pods, Applications, Events, Logs.
Niemals Secret-Werte ausgeben — nur Namen, Conditions und Events.

## Sprache

Kommentare und Doku auf IT-Deutsch, Fachbegriffe englisch, innerhalb eines
Absatzes keine Sprachmischung. Kommentare nur dort, wo sie etwas tragen, das
der Code nicht sagt; Erzählteile gehören in die `README.md` der App, nicht ins
Manifest.
