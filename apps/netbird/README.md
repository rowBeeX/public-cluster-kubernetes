# NetBird

WireGuard-basiertes VPN-Management für den Public-Cluster und verbundene Clients.

## Komponenten

| Ressource | Beschreibung |
|-----------|-------------|
| netbird-server StatefulSet | Management-Server (HTTP + STUN UDP 3478) |
| netbird-dashboard Deployment | Web-UI (2 Replicas) |
| netbird-stun Service | STUN-Dienst mit `externalIPs` auf den Cilium-Nodes |
| netbird-relay Deployment | WebSocket-Relay (§8/§21), Port 33080, öffentlich `rels://netbird-relay.dev5.sedware.net:443` |

## Besonderheiten

- `externalIPs` im netbird-stun Service sind hartkodiert auf `[192.168.101.10, 192.168.101.11]`
  (die beiden Gateway-Nodes) — bei IP-Änderungen muss `base/resources.yaml` manuell angepasst werden
- UDP 3478 ist für STUN aus der Cilium-Entity `world` freigegeben
- Config kommt aus dem `netbird-config` Secret (SOPS via `public-cluster-nix`)
- Lange Envoy-Streams (Signal-gRPC, Relay-WebSocket) werden per
  `BackendTrafficPolicy` `netbird-longlived-streams` (`streamIdleTimeout: 24h`)
  offengehalten — ersetzt das alte Cilium-Setting `proxy-stream-idle-timeout-seconds=86400`

## Relay: manueller Secret-/Config-Schritt (nicht automatisierbar)

Das Relay teilt sich ein HMAC-Secret mit dem Management-Server. Beides muss
out-of-band (SOPS via `public-cluster-nix`, wie `netbird-config`) bereitgestellt
werden — hier werden **keine** echten Secret-Werte hinterlegt:

1. Secret `netbird-relay-auth` (Namespace `app-netbird`) mit Key `NB_AUTH_SECRET`
   anlegen (starker Zufallswert). Wird vom Relay-Deployment via `secretKeyRef` gelesen.
2. In der Management-Config (`netbird-config` → `config.yaml`) den `Relay`-Block
   ergänzen — Wert von `Secret` **identisch** zu `NB_AUTH_SECRET` oben:

   ```json
   "Relay": {
       "Addresses": ["rels://netbird-relay.dev5.sedware.net:443"],
       "CredentialsTTL": "24h",
       "Secret": "<gleicher Wert wie NB_AUTH_SECRET>"
   }
   ```

3. DNS-Record `netbird-relay.dev5.sedware.net` auf die Gateway-Nodes zeigen lassen
   (analog zu den übrigen `*.dev5.sedware.net` Hosts).

## Zugang

- Dashboard: `https://netbird.dev5.sedware.net/` (nur über VPN)
- Management API: intern via `netbird-server.app-netbird.svc`
