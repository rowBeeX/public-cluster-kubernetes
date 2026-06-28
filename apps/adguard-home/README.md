# AdGuard Home

DNS-Resolver mit Rewrite-Regeln für den Public-Cluster.

## Besonderheiten

- Läuft mit `hostNetwork: true` auf Port 53 (DNS) und 3000 (Web-UI)
- `pod-security.kubernetes.io/enforce: privileged` wegen hostNetwork
- NodeSelector: `public.sedware.net/control-plane: "true"` (nur Host-1)
- Bootstrap-Konfiguration kommt aus dem `adguard-config` Secret (SOPS)

## Zugang

- Web-UI: `https://adguard.dev0.sedware.net/` (nur über NetBird)
- DNS: UDP/TCP 53 auf den HAProxy-Hosts (192.168.101.10, 192.168.101.11)
