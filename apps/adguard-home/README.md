# AdGuard Home

DNS-Resolver mit Rewrite-Regeln für den Public-Cluster.

## Besonderheiten

- Läuft mit `hostNetwork: true` auf Port 53 (DNS) und 3000 (Web-UI)
- `pod-security.kubernetes.io/enforce: privileged` wegen hostNetwork
- NodeSelector: `public.sedware.net/control-plane: "true"` (nur Host-1)
- Bootstrap-Konfiguration kommt aus dem `adguard-config` Secret (SOPS)

## Zugang

- Web-UI: nur über NetBird erreichbar (keine öffentliche Envoy-Route, kein öffentlicher DNS-Eintrag)
- DNS: UDP/TCP 53 direkt auf Host-1 (hostNetwork), nur für NetBird-Peers und ausdrücklich erlaubte interne Quellen — kein offener öffentlicher Resolver
