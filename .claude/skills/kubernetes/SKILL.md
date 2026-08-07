---
name: kubernetes
description: Den Public-k3s-Cluster und seine Argo-CD-Applikationen betreiben und diagnostizieren.
---

# Public k3s Cluster

- Kubernetes-Befehle über `public-cluster-host-1` mit `sudo k3s kubectl`
  ausführen; nie einen unabhängigen lokalen Kontext verwenden.
- Git ist die Source of Truth. Argo-CD-verwaltete Ressourcen nicht dauerhaft
  live patchen.
- `public-cluster-host-1` ist die einzige Control-Plane; `public-cluster-host-2`
  ist ein Agent und noch nicht beschafft, der Cluster läuft daher aktuell
  allein auf Host 1. Das ist bewusst nicht HA.
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
  ist per Contract verboten (`validate.sh` #7). AdGuard DNS :53 läuft
  hostNetwork über das NetBird-Overlay.
- `public-shared-bulk` (SMB CSI gegen eine Hetzner StorageBox; es gibt hier
  kein NFS) nur für gemeinsame Bulk-/RWX-Daten verwenden. Datenbanken bleiben
  auf explizitem node-lokalem Storage, sofern ihr eigenes HA-Design nichts
  anderes vorgibt.
- Niemals Secret-Werte ausgeben. Nur Namen, Conditions und Events inspizieren.
- Die gerenderten Apps mit
  `cluster-testing/public-cluster/kubernetes/validate.sh` validieren, danach
  Nodes, Pods, Applications, Events und relevante Logs auf Host 1 inspizieren.
