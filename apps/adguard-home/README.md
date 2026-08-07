# AdGuard Home

DNS-Resolver mit Rewrite-Regeln für den Public-Cluster.

## Besonderheiten

- Läuft mit `hostNetwork: true` auf Port 53 (DNS) und 3000 (Web-UI)
- `pod-security.kubernetes.io/enforce: privileged` wegen hostNetwork
- NodeSelector: `public.sedware.net/control-plane: "true"` (nur Host-1)
- Bootstrap-Konfiguration kommt aus dem `adguard-config` Secret (SOPS)

## Zugang

- Web-UI: `https://adguard.sedware.net` über den öffentlichen Envoy-Edge
  (Wildcard-TLS). Erreichbarkeit ist per `SecurityPolicy` auf die NetBird-Overlay-
  CIDR `100.64.0.0/10` beschränkt — Envoy weist jeden anderen Client ab, die UI
  ist also nie aus dem Internet erreichbar. Kein öffentlicher DNS-Eintrag; NetBird-
  Clients lösen `adguard.sedware.net` über AdGuard auf die Host-1-Overlay-IP
  auf und treffen dort den ko-lokalen Envoy.
- DNS: UDP/TCP 53 direkt auf Host-1 (hostNetwork). Die Host-Firewall gibt :53
  ausschließlich auf dem NetBird-Interface `nb-wt0` frei; auf allen anderen
  Interfaces wird der Port verworfen — kein offener öffentlicher Resolver
