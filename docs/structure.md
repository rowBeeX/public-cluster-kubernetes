# Repository-Struktur

```text
apps/
  adguard-home/               DNS/UI, ausschließlich NetBird-intern (Envoy-Route per SecurityPolicy auf NetBird begrenzt)
  authentik/                  öffentlicher OIDC-Provider (Envoy Gateway)
  mail-edge/                  Mail Edge / MX-Relay (SMTP :25 eingehend + ausgehendes Relay via Envoy :2525)
  netbird/                    Dashboard/Management/Signal/Relay (Envoy Gateway)
  postgresql/                 CNPG-Cluster als Backend für Authentik
  valkey/                     Cache-/Session-Store als Backend für Authentik

  <app>/                      jedes App-Verzeichnis hat dasselbe flache Layout:
    argocd.yaml               Argo-CD-Markerdatei, die vom ApplicationSet entdeckt wird
    README.md
    kustomization.yaml        listet die Manifeste in der unten stehenden Reihenfolge
    namespace.yaml            Namespace, LimitRange, ResourceQuota
    workload.yaml             Workloads, Services, PVCs, Certificates, Vault* …
    networkpolicy.yaml        CiliumNetworkPolicies (Default-Deny + Allow)
docs/
  app-layout.md
  architecture.md
  exceptions.md
  structure.md
```

Es gibt keine `base/`- oder `overlays/`-Verzeichnisse: es gibt nur eine
Umgebung, daher ist jede App ein einzelnes flaches Kustomize-Verzeichnis, das
Argo CD aus `apps/<name>` synchronisiert. Eine App darf neben den drei oben
genannten Dateien weitere Manifeste ergänzen (zum Beispiel
`apps/mail-edge/tcproute.yaml`); `kustomization.yaml` listet sie auf.

Envoy Gateway und Zertifikate liegen in `public-cluster-nix`. Die
HTTP-/gRPC-/WebSocket-Exposition der Applikationen liegt hier als `HTTPRoute`
und `GRPCRoute` am Envoy Gateway; eingehende Mail-, STUN- und DNS-Pfade nutzen
protokollspezifische Services statt Envoy (nur der ausgehende Smarthost-Pfad
ist eine `TCPRoute` am NetBird-only-Envoy-Listener `:2525`).
Kubernetes-`Ingress`, `NetworkPolicy`, Traefik-Ressourcen und HTTP-NodePorts
sind verboten und werden von
`cluster-testing/public-cluster/kubernetes/validate.sh` geprüft.

## Dokumentationssprache

Kommentare und Dokumentation sind auf IT-Deutsch verfasst; Fachbegriffe
bleiben englisch. Innerhalb eines Satzes oder Absatzes werden keine Sprachen
gemischt.
