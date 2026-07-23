# NetBird

WireGuard-basiertes VPN-Management für den Public-Cluster und verbundene Clients.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| netbird-server StatefulSet | Combined-Server: Management, Signal, **eingebetteter Relay** und STUN (UDP 3478) |
| netbird-dashboard Deployment | Web-UI (2 Replicas) |
| netbird-stun Service | STUN-Dienst per Cilium Node IPAM auf den Gateway-Nodes |

## Besonderheiten

- Cilium Node IPAM übernimmt die Adressen aller Nodes mit
  `gateway.sedware.net/enabled=true`; Kubernetes-1.36-`externalIPs` und
  LoadBalancer-NodePorts werden nicht verwendet
- UDP 3478 ist für STUN aus der Cilium-Entity `world` freigegeben
- Config kommt aus dem `netbird-config` Secret (SOPS via `public-cluster-nix`)
- Lange Envoy-Streams (Signal-gRPC, Relay-WebSocket) werden per
  `BackendTrafficPolicy` `netbird-longlived-streams` (`streamIdleTimeout: 24h`)
  offengehalten — ersetzt das alte Cilium-Setting `proxy-stream-idle-timeout-seconds=86400`

## Relay (im Combined-Server eingebettet)

Der `netbird-server` (`netbirdio/netbird-server`) enthält Relay und STUN bereits
eingebettet und kündigt den Relay unter seiner `exposedAddress` als
`rels://netbird-control.<domain>:443` an — ein separates Relay-Deployment, ein
eigener DNS-Record oder ein HMAC-Secret (`netbird-relay-auth`) ist **nicht** nötig.

Der Relay-WebSocket läuft im Server auf Container-Port 80, demselben Port wie der
gRPC-Pfad (Management/Signal). Am Envoy-Gateway spricht dieser Port für gRPC `h2c`;
das WebSocket-Upgrade des Relays braucht aber HTTP/1.1. Andernfalls beantwortet
Envoy das Upgrade mit `502` und der Peer meldet „relay client not connected".
Deshalb:

- Der Service `netbird-server` hat einen zweiten Port `relay-ws` (8080 →
  Container-Port 80) **ohne** `appProtocol`, sodass Envoy dorthin HTTP/1.1 spricht.
- Die HTTPRoute `netbird-control-relay` leitet den spezifischeren Pfad `/relay`
  (Vorrang vor der `/`-Route) auf `netbird-server:8080`.

> Hinweis: Ein `server.relays`-Block in der Management-Config würde den
> eingebetteten Relay **und** STUN abschalten (netbird #5351). Da STUN hier im
> Server verbleibt, wird der eingebettete Relay genutzt — kein `relays`-Block in
> `config.yaml`, kein externes Relay-Deployment.

## Zugang

- Dashboard: `https://netbird.dev11.sedware.net/` — öffentlich über den Envoy-Edge
  (`public-dev`) per HTTPRoute erreichbar; abgesichert durch Authentik-OIDC-Login,
  nicht durch eine Netzwerk-/CNP-Beschränkung
- Management API: intern via `netbird-server.app-netbird.svc`
