# mail-edge — Public Mail Edge / MX-Relay

Der verbindliche öffentliche Mail-Ein- **und** -Ausgang für das selbst
gehostete Mail-System. Es gibt **keinen User-Login** (kein öffentliches
IMAP/JMAP/ManageSieve/Submission).

```
Eingehend: Internet :25 ─▶ Mail Edge (Host 1 oder Host 2) ─▶ Local Stalwart (über NetBird) :25
Ausgehend: Local Stalwart ─▶ Public Envoy Host 1 :2525 ─▶ Mail Edge :25 ─▶ Internet :25
```

Die beiden Richtungen sind unterschiedlich redundant: eingehende Internet-Mail
nehmen **beide** Nodes an (die A/AAAA-Records von `mail.sedware.net` zeigen im
Round-Robin auf beide Public-Hosts, und je Gateway-Node läuft ein
mail-edge-Pod). Ausgehende Mail läuft dagegen über einen **festen Einzel-Peer**,
`public-cluster-host-1.nb.sedware.net:2525`; siehe **Bekannter offener Punkt**
unten.

Direktes Internet→Local-Stalwart und direktes Local-Stalwart→Internet sind
verboten; dieser Pod ist in beiden Richtungen der einzige Pfad.

Beide Richtungen sind deklarativ implementiert. Internet-MX-Absender dürfen
die SMTP-Session öffnen, können aber wegen `reject_unauth_destination` nur
lokale Empfänger adressieren. Ausgehend erreicht Stalwart den privaten
Envoy-Listener `:2525` über NetBird; dessen TCPRoute terminiert an
Postfix `:25`.

Der Edge betreibt **Postfix** (`boky/postfix`): ein vollständig deklaratives,
k8s-natives SMTP-Relay, dessen gesamte Konfiguration über Env-Vars läuft (das
Image wendet jeden `POSTFIX_<param>` per `postconf` an), ohne Datenspeicher
und ohne Accounts.

## Konfiguration der beiden Richtungen

- **Eingehendes MX** — `POSTFIX_relay_domains=sedware.net` nimmt Mail für die
  Domain an; `POSTFIX_transport_maps=inline:{ sedware.net=smtp:[<stalwart>]:25 }`
  leitet sie an das Local-Stalwart-Backend weiter (`[...]` = keine MX-Auflösung).
- **Ausgehendes Relay** — die Anti-Open-Relay-Grenze ist
  `smtpd_relay_restrictions = permit_mynetworks reject_unauth_destination`:
  Relaying an beliebige Ziele erfordert, dass die Quelle in
  `POSTFIX_mynetworks` steht. Das ist auf Loopback plus die PodCIDRs beider
  Gateway-Nodes `10.42.0.0/24` (Host 1) und `10.42.1.0/24` (Host 2) begrenzt.
  Der Smarthost-Pfad endet am hostNetwork-Envoy des Nodes, den Stalwart
  adressiert, und erscheint bei Postfix mit dessen CiliumInternalIP aus dem
  jeweiligen PodCIDR. Genutzt wird davon derzeit nur `10.42.0.0/24`, weil
  Stalwart ausschließlich Host 1 anspricht; `10.42.1.0/24` steht vorsorglich
  dort, damit ein Umschwenken auf Host 2 nicht zusätzlich an Postfix scheitert.
  Vertraut wird bewusst nur diesen beiden `/24`, nicht dem gesamten
  `10.42.0.0/16`, sonst dürfte jeder Pod im Cluster nach außen relayen. Cilium
  lässt am Backend nur die Host-/Remote-Node-Identity durch. Der frühere Wert
  `100.64.0.0/10` hätte dem gesamten NetBird-/CGNAT-Overlay vertraut und ein
  Open-Relay-Risiko erzeugt. Die Relay-Client-Identität ist deklarativ in
  NetBird modelliert (Gruppen
  `mail-edge` / `mail-relay-client` + Policy `mail-relay`, provisioniert durch
  `cluster-testing/public-cluster/nix/cluster/provision_mail_relay_policy.py`);
  seit der NetBird-Least-Privilege-Umstellung `Default All→All` entfernt hat,
  ist diese Policy die durchsetzende Zugriffskontrolle für den Relay-Pfad.
- **TLS** — STARTTLS auf :25 mit dem cert-manager-`Certificate` `mail-edge-tls`
  (SANs `mail.sedware.net` und `public-cluster-host-1.nb.sedware.net`, DNS-01
  über ClusterIssuer `letsencrypt`). Das gateway-system-Wildcard-Secret wird
  bewusst nicht namespaceübergreifend wiederverwendet. Der zweite SAN deckt
  genau den Peer ab, den Stalwart für den Smarthost anspricht; für Host 2 gibt
  es keinen SAN.

## Exposition & Sicherheit

- Der eingehende Service `mail-edge-smtp` nutzt Cilium Node IPAM auf allen
  Nodes mit Label `gateway.sedware.net/enabled=true`. Er nutzt weder das
  veraltete `externalIPs` noch LoadBalancer-NodePorts und läuft nicht über
  Envoy.
- Host-Firewall: TCP 25 wird auf dem internetseitigen Interface der
  Gateway-Nodes in `public-cluster-nix` geöffnet (`roles/public/gateway-node.nix`),
  analog zur UDP-3478-STUN-Regel. Node-Adressänderungen erfordern kein
  Manifest-Update.
- CiliumNetworkPolicies: Default-Deny; Ingress :25 von `world` (MX) und von
  `host`/`remote-node` (der hostNetwork-Envoy, der den privaten :2525-
  Relay-Pfad trägt); Egress DNS; Egress :25 zu `world` (Zustellung) und zum
  NetBird-Overlay-CIDR `100.64.0.0/10` (eingehende Weiterleitung an Stalwart).
  Keine Login-Ports.
- PSA: Der Namespace erzwingt **baseline** (Audit/Warn restricted). Der
  Postfix-Master benötigt UID 0 (privilege-separated Design), restricted ist
  daher nicht erreichbar; der Container droppt `ALL` und ergänzt nur die acht
  von Postfix benötigten Capabilities (siehe `docs/exceptions.md`), nutzt
  seccomp RuntimeDefault und deaktiviert Privilege-Escalation.
- StatefulSet mit 2 Replicas und je Pod einem eigenen RWO-Volume aus
  `volumeClaimTemplates` (`spool-mail-edge-0` und `spool-mail-edge-1`).
  Zurückgestellte Mail muss Restarts überstehen, und ein Postfix-Spool kann
  nicht über mehrere Replicas geteilt werden; die beiden Warteschlangen laufen
  deshalb unabhängig, wie bei zwei gleichrangigen MX üblich. Eine harte
  `podAntiAffinity` über `kubernetes.io/hostname` verteilt die Pods auf beide
  Gateway-Nodes — genau das ist die Voraussetzung dafür, dass der Service mit
  `externalTrafficPolicy: Local` auf beiden öffentlichen Adressen :25
  ausliefert und die echte Client-IP sieht. Diese Verteilung betrifft den
  **eingehenden** Weg; der ausgehende Smarthost-Pfad hängt davon unabhängig an
  Host 1 (siehe **Bekannter offener Punkt**).

## Integrationspunkte

- **Local-Stalwart-Backend.** `POSTFIX_transport_maps` leitet `sedware.net`
  an `smtp:[beelink-server.nb.sedware.net]:25` weiter — der stabile
  NetBird-Peer-FQDN des Local Private Edge, bei Zustellung aufgelöst. Das
  ausgehende Relay-Vertrauen ist auf Loopback und die PodCIDRs beider
  Public-Hosts begrenzt (`POSTFIX_mynetworks`); siehe **Ausgehendes Relay**
  oben.
- **Erreichbarkeit Local Stalwart → Mail Edge.** Stalwart verbindet sich zu
  `public-cluster-host-1.nb.sedware.net:2525` — gesetzt über `MAIL_RELAY_HOST`
  in `local-cluster-kubernetes/apps/stalwart/seed-noreply-account-job.yaml`.
  Der Listener ist nur auf `nb-wt0` geöffnet und leitet per TCPRoute an diesen
  Service weiter.
- **DNS.** Ein MX-Record `sedware.net` → `mail.sedware.net` sowie A/AAAA-Records
  `mail.sedware.net` → die öffentlichen Adressen beider Gateway-Nodes
  (Round-Robin), dazu SPF/DKIM/DMARC, werden über Cloudflare veröffentlicht
  (außerhalb des Scopes dieses Manifests).

## Bekannter offener Punkt: ausgehende Mail ist nicht redundant

Der ausgehende Weg hat kein Round-Robin und kein Failover. `MAIL_RELAY_HOST`
zeigt fest auf `public-cluster-host-1.nb.sedware.net:2525`, und das
STARTTLS-`Certificate` `mail-edge-tls` trägt nur diesen einen Peer-FQDN als SAN.
Fällt Host 1 aus, nimmt der eingehende MX über Host 2 weiter Mail an, der
ausgehende Weg steht dagegen still, bis beide Werte auf Host 2 umgestellt sind.

Vorbereitet ist das Umschalten bereits an den Stellen, die sich sonst still
querstellen würden: die NetBird-Gruppe `mail-edge` enthält beide Public-Hosts
(`provision_mail_relay_policy.py`), und `POSTFIX_mynetworks` vertraut neben
`10.42.0.0/24` auch `10.42.1.0/24`. Offen bleiben `MAIL_RELAY_HOST` und der
zweite Zertifikats-SAN. Das ist eine bewusste Beschränkung des aktuellen
Aufbaus, kein Konfigurationsfehler.
