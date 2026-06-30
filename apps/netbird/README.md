# NetBird

WireGuard-basiertes VPN-Management für den Public-Cluster und verbundene Clients.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| netbird-server StatefulSet | Management-Server (HTTP + STUN UDP 3478) |
| netbird-dashboard Deployment | Web-UI (2 Replicas) |
| netbird-stun Service | STUN-Dienst mit `externalIPs` auf den Cilium-Nodes |

## Besonderheiten

- `externalIPs` im netbird-stun Service sind hartkodiert auf `[192.168.101.10, 192.168.101.11]`
  (die beiden Gateway-Nodes) — bei IP-Änderungen muss `base/resources.yaml` manuell angepasst werden
- UDP 3478 ist für STUN aus der Cilium-Entity `world` freigegeben
- Config kommt aus dem `netbird-config` Secret (SOPS via `public-cluster-nix`)

## Zugang

- Dashboard: `https://netbird.dev1.sedware.net/` (nur über VPN)
- Management API: intern via `netbird-server.app-netbird.svc`
