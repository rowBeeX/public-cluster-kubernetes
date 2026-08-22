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
  `BackendTrafficPolicy` `netbird-longlived-streams` offengehalten
  (`requestTimeout: 0s`, `streamIdleTimeout: 24h`); ohne sie trennt Envoy
  Gateway den server-streaming Sync-RPC nach 15 Sekunden
- `netbird.sedware.net` ist der einzige Edge-Name mit
  `Strict-Transport-Security: max-age=31536000; includeSubDomains` — alle
  anderen tragen nur `max-age`. Die Quelle ist weder das Gateway noch dieses
  Manifest, sondern das Dashboard-Image selbst
  (`/etc/nginx/http.d/default.conf` setzt den Header zweimal per `add_header …
  always`). Der Gateway-weite Header steht in `public-cluster-nix`
  (`manifests/platform/gateway/00-public-gateway.yaml.in`) bewusst als
  `lateResponseHeaders.addIfAbsent` und lässt den Wert des Backends deshalb
  stehen. Das ist unschädlich und bleibt so: `includeSubDomains` gilt nur für
  `*.netbird.sedware.net`, nicht für `*.sedware.net` — der Grund für den
  Verzicht am Edge (die Klartext-AdGuard-UI auf `*.nb.sedware.net:3000`) liegt
  in einem anderen Namenszweig. Wer den Wert dennoch vereinheitlichen will,
  braucht einen `ResponseHeaderModifier`-`set` auf der HTTPRoute hier, nicht
  eine Änderung am Gateway.

## Der Sprung von Server 0.76.3 auf 0.77.1

Das Overlay trägt die gesamte Steuerstrecke zwischen beiden Clustern; ein
Fehlschlag hier kappt sie. Deshalb sind die zwei Fragen, die zählen, gemessen
statt vermutet:

**Die Clients bleiben kompatibel.** Auf allen vier Hosts läuft `netbird
v0.71.4`, der Server geht auf `0.77.1` — sechs Minor-Versionen Abstand. Die
gRPC-Schnittstelle `shared/management/proto/management.proto` ist zwischen
diesen beiden Tags **rein additiv**: kein entferntes Feld, keine
wiederverwendete Feldnummer, keine geänderte Feldbedeutung. Das neue
Wire-Format für die Network-Map (`NetworkMapEnvelope`, Feld 8) greift
ausdrücklich nur bei Peers, die `PeerCapabilityComponentNetworkMap`
annoncieren; ein 0.71.4-Client tut das nicht und bekommt weiter die expandierte
`NetworkMap` in Feld 5.

Der einzige entfernte Pfad in dieser Spanne ist der deprecated
Hello-Handshake des Relays (0.75.0). Er wurde in **v0.29.1** durch den
Auth-Handshake ersetzt — er bediente nur Clients vor v0.29.1 und ist für
v0.71.4 ohne Bedeutung.

**Die SQLite-Datenbank bekommt genau eine neue Migration.** Verglichen wurden
die Migrationsketten von `management/server/store/store.go` in beiden Tags:
identisch bis auf `MigrateAgentNetworkSettingsToDomain`. Die formt
`agent_network_settings` von `(cluster, subdomain)` auf `(domain,
proxy_address)` um und **löscht die beiden alten Spalten** — vorwärtsgerichtet,
kein Rückweg über einen Image-Rollback. Gemessen in `store.db`: die Tabelle
existiert mit den Altspalten, hat aber **0 Zeilen**, und keine Zeile mit
leerem `cluster`/`subdomain`, an der die Migration laut ihrem eigenen Kommentar
laut scheitern würde. Es geht also nichts verloren; der Rückhalt ist der
stündliche btrfs-Snapshot des `@persist`-Subvolumes, in dem das PVC liegt.

Reihenfolge: Server vor Dashboard. Danach die Least-Privilege-Policies und die
Nameserver-Gruppe erneut prüfen — beide sind live über
`provision_netbird_least_privilege.py` gesetzt und nicht Teil dieses Repos.

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

- Dashboard: `https://netbird.sedware.net/` — öffentlich über den Envoy-Edge
  (`public`) per HTTPRoute erreichbar; abgesichert durch Authentik-OIDC-Login,
  nicht durch eine Netzwerk-/CNP-Beschränkung
- Management API: intern via `netbird-server.app-netbird.svc`
