# gitlab-runner — CI-Runner im Public-Cluster für das LOKALE GitLab

Zwei Runner-Manager mit Kubernetes-Executor. Die GitLab-Instanz, an der sie
hängen, läuft **nicht** hier, sondern im lokalen Cluster; erreicht wird sie
ausschließlich über das NetBird-Overlay.

```
gitlab-runner-amd64 (Host 1) ─┐
                              ├─▶ NetBird ─▶ https://gitlab.local.sedware.net
gitlab-runner-arm64 (Host 2) ─┘             (lokaler Cluster, 100.64.0.0/10)
```

## Der Pfad zum lokalen GitLab

`gitlab.local.sedware.net` löst über die NetBird-DNS-Gruppe auf die
Overlay-Adresse des lokalen Managers auf — kein öffentlicher Cloudflare-Record,
kein Weg über den Public-Edge. Cilium sieht das Ziel deshalb als CIDR und nicht
als Cluster-Endpoint, weshalb die Egress-Regel `allow-gitlab-egress` ein
`toCIDRSet: 100.64.0.0/10` auf `:443` ist. Fällt NetBird auf einem der beiden
Hosts aus, verliert genau dessen Manager die Verbindung; die Jobs der anderen
Architektur laufen weiter.

Job-Pods klonen über denselben Weg (`allow-job-pods`, ebenfalls
`100.64.0.0/10:443`) und dürfen zusätzlich nach `world:80/443`, um
Paketregistries zu erreichen.

## Der Runner darf nicht neuer sein als der Server

GitLab liefert Runner und Server als eine Versionsreihe aus und stützt sich
darauf, dass der Runner höchstens so neu ist wie die Instanz, gegen die er
registriert ist. Der Server ist das GitLab in
`local-cluster-kubernetes/apps/gitlab` — ein **anderes Repository**, und
gemessen am 2026-08-22 läuft er auf `v19.2.1`.

Der hier gepinnte `alpine-v19.3.0` ist damit **eine Minor-Version vor dem
Server**. Vor dem Ausrollen dieses Repos muss deshalb der GitLab-Bump auf
`v19.3.0` im lokalen Repo liegen. Ohne ihn läuft der Runner voraussichtlich
weiter, aber in einer von Upstream nicht abgedeckten Kombination.

Kein `helper_image` ist gepinnt (`config.toml` in `workload.yaml`) — der Runner
wählt das zu seiner eigenen Version passende Helper-Image selbst. Der Bump
zieht es also automatisch mit; ein zweiter Pin, der auseinanderlaufen könnte,
existiert nicht.

## Warum zwei Deployments statt einem

`kubernetes.io/arch` unterscheidet sie: Host 1 ist amd64, Host 2 aarch64. Tags
hängen serverseitig am **Runner**, nicht am Manager — mit einem gemeinsamen
Token ließen sich Jobs nicht nach Architektur lenken. Jeder Manager benutzt
daher einen eigenen Token (`runner-token-amd64` / `runner-token-arm64` aus dem
`VaultStaticSecret` `gitlab-runner-auth`) und setzt für seine Job-Pods
`[runners.kubernetes.node_selector] "kubernetes.io/arch"` auf die eigene
Architektur.

`strategy: Recreate` statt RollingUpdate: zwei Manager mit demselben Token
würden sich während des Wechsels kurzzeitig dieselben Jobs teilen.

Das Runner-Image `docker.io/library/alpine` in der `config.toml` ist aus
demselben Grund an einen **Multi-Arch-Index** gepinnt, nicht an einen
amd64-Child-Digest.

## Warum handgeschrieben statt des offiziellen Charts

Das ApplicationSet dieses Clusters kennt nur `path` und rendert mit
`kubectl kustomize` — es gibt keine Helm-Quelle. Zweitens besitzt der hiesige
`argocd-application-controller` weder `escalate` noch `bind`; die Role des
Charts (`apiGroups: [""], resources: ["*"], verbs: ["*"]`) wäre hier gar nicht
anlegbar. Die Role in `workload.yaml` ist auf das eingeschränkt, was der
Kubernetes-Executor tatsächlich braucht.

## Token und Konfiguration

`config.toml` entsteht beim Start per `sed` aus der ConfigMap-Vorlage in einem
`emptyDir`; der Token kommt über eine Umgebungsvariable und steht damit nie in
einer ConfigMap. Erzeugt wird er im lokalen Cluster
(`<Monorepo>/cluster-tools/local/nix/cluster/provision_gitlab_runner.py`) und
von dort in den PUBLIC-Vault gespiegelt — nur der dortige Toolbox-Pod kann ihn
am GitLab anlegen.

## Pod Security

Der Namespace erzwingt `restricted` und steht deshalb **nicht** in
`gates/exceptions.md`. Das gilt auch für die vom Runner selbst erzeugten
Job-Pods: `config.toml` setzt für Build-, Helper- und Init-Container
`run_as_non_root`, `cap_drop = ["ALL"]` und
`allow_privilege_escalation = false`. Die letzte Zeile prüft
`<Monorepo>/public-cluster-kubernetes/validate.sh` ausdrücklich gegen
diese Datei — ein fehlender Schlüssel wäre per Default zwar sicher, aber
nicht nachweisbar.

Die `ResourceQuota` ist bewusst knapp und verbietet PVCs, NodePorts und
LoadBalancer: ein entlaufener CI-Job darf auf den Gateway-Nodes nichts reißen.
