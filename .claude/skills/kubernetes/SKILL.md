---
name: kubernetes
description: Workloads dieses Repos im Public-k3s deployen und diagnostizieren — Zugriff über Host 1, der HTTP-/TLS-Pfad, Node-IPAM-Sonderfälle, Storage und die Validierung. Verwenden beim Hinzufügen oder Ändern einer App und bei 404/502/504 gegen einen öffentlichen Namen.
---

# Public k3s Cluster

- Kubernetes-Befehle über `public-cluster-host-1` mit `sudo k3s kubectl`
  ausführen; nie einen unabhängigen lokalen Kontext verwenden.
- Git ist die Source of Truth. Argo-CD-verwaltete Ressourcen nicht dauerhaft
  live patchen.
- `public-cluster-host-1` ist die einzige Control-Plane; `public-cluster-host-2`
  ist ein in Betrieb befindlicher aarch64-Agent. Der Cluster hat damit zwei
  Nodes, aber nur eine Control-Plane — das ist bewusst nicht HA.
- HTTP-Pfad: externes DNS (explizite A/AAAA-Records je Public-Edge-Host unter
  `sedware.net`, bewusst kein öffentlicher Wildcard) -> öffentliches Envoy
  Gateway (`public` im Namespace `gateway-system`, hostNetwork auf den
  Gateway-Nodes) -> HTTPRoute -> ClusterIP-Service -> Pod. TLS terminiert am
  Envoy Gateway mit dem cert-manager-Wildcard-Zertifikat `public-wildcard`
  (Secret `public-wildcard-tls`, Cloudflare DNS-01).
  In diesem Pfad gibt es kein HAProxy, Traefik, NodePort oder Kubernetes
  Ingress.
- Raw-TCP/UDP-Sonderfälle (NetBird STUN, Mail-Edge SMTP) werden über explizite
  Cilium-Node-IPAM-`LoadBalancer`-Services exponiert (`loadBalancerClass:
  io.cilium/node`, NodePorts deaktiviert), nicht über Envoy; `spec.externalIPs`
  ist per Contract verboten (`validate.sh` prüft das). AdGuard DNS :53 läuft
  hostNetwork über das NetBird-Overlay.
- `public-shared-bulk` (SMB CSI gegen eine Hetzner StorageBox; es gibt hier
  kein NFS) nur für gemeinsame Bulk-/RWX-Daten verwenden. Datenbanken bleiben
  auf explizitem node-lokalem Storage, sofern ihr eigenes HA-Design nichts
  anderes vorgibt.
- Niemals Secret-Werte ausgeben. Nur Namen, Conditions und Events inspizieren.
- Die gerenderten Apps mit
  `cluster-testing/public-cluster/kubernetes/validate.sh` validieren, danach
  Nodes, Pods, Applications, Events und relevante Logs auf Host 1 inspizieren.

## Beim Debuggen leicht zu übersehen

- Die **Envoy-Proxy-Pods liegen in `envoy-gateway-system`**, nur das
  `Gateway`-Objekt in `gateway-system`. Ihre Container sind distroless:
  `kubectl exec` schreibt den Fehler nach stderr und lässt stdout **leer** — in
  eine Pipe geschoben sieht das aus wie „Zähler ist null". Zähler stattdessen
  vom Host holen: `curl -s http://127.0.0.1:19000/stats`.
- **Envoys `connectionIdleTimeout` (30 s) muss kleiner sein als das Keep-Alive
  des Backends.** Ist es größer, schreibt Envoy in tote Verbindungen und die
  Anfrage versandet bis zum Route-Timeout — die Ursache reproduzierbarer 504er.
  Node.js und Apache liegen per Default bei 5 s. Herleitung in
  `../docs/02-anfragewege.md`.
- **Logs und Metriken dieses Clusters liegen im Local-Cluster**, unterschieden
  über das Label `cluster="public"`. Wie man sie ohne Gateway-BasicAuth
  abfragt, steht in
  `../local-cluster-nix/.claude/skills/observability/SKILL.md`.
- Bevor ein Dauerzustand als neuer Befund gemeldet wird:
  `../docs/09-offene-punkte.md` lesen.
