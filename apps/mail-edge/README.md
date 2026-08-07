# mail-edge — Public Mail Edge / MX-Relay

Der verbindliche öffentliche Mail-Ein- **und** -Ausgang für das selbst
gehostete Mail-System. Es gibt **keinen User-Login** (kein öffentliches
IMAP/JMAP/ManageSieve/Submission).

```
Eingehend: Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (über NetBird) :25
Ausgehend: Local Stalwart ─▶ Public Envoy :2525 ─▶ Mail Edge :25 ─▶ Internet :25
```

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
  `POSTFIX_mynetworks` steht. Das ist jetzt auf Loopback plus das PodCIDR des
  einzelnen Server-Nodes `10.42.0.0/24` begrenzt. Cilium lässt am Backend nur
  die Host-/Remote-Node-Identity durch; ein zweiter Node läge separat in
  `10.42.1.0/24`. Der frühere Wert `100.64.0.0/10` hätte dem gesamten
  NetBird-/CGNAT-Overlay vertraut und ein Open-Relay-Risiko erzeugt. Die
  Relay-Client-Identität ist deklarativ in NetBird modelliert (Gruppen
  `mail-edge` / `mail-relay-client` + Policy `mail-relay`, provisioniert durch
  `cluster-testing/public-cluster/nix/cluster/provision_mail_relay_policy.py`);
  seit der NetBird-Least-Privilege-Umstellung `Default All→All` entfernt hat,
  ist diese Policy die durchsetzende Zugriffskontrolle für den Relay-Pfad.
- **TLS** — STARTTLS auf :25 mit dem cert-manager-`Certificate` `mail-edge-tls`
  (SANs `mail.sedware.net` und `public-cluster-host-1.nb.sedware.net`, DNS-01
  über ClusterIssuer `letsencrypt`). Das gateway-system-Wildcard-Secret wird
  bewusst nicht namespaceübergreifend wiederverwendet.

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
- Ein Replica + RWO-PVC `mail-edge-spool` für die Queue (zurückgestellte Mail
  muss Restarts überstehen; ein Postfix-Spool kann nicht über mehrere Replicas
  geteilt werden).

## Integrationspunkte

- **Local-Stalwart-Backend.** `POSTFIX_transport_maps` leitet `sedware.net`
  an `smtp:[beelink-server.nb.sedware.net]:25` weiter — der stabile
  NetBird-Peer-FQDN des Local Private Edge, bei Zustellung aufgelöst. Das
  ausgehende Relay-Vertrauen ist jetzt auf Loopback und das PodCIDR von Public
  Host 1 begrenzt (`POSTFIX_mynetworks`); siehe **Ausgehendes Relay** oben.
- **Erreichbarkeit Local Stalwart → Mail Edge.** Stalwart verbindet sich zu
  `public-cluster-host-1.nb.sedware.net:2525`. Der Listener ist nur auf
  `nb-wt0` geöffnet und leitet per TCPRoute an diesen Service weiter.
- **DNS.** Ein MX-Record `sedware.net` → `mail.sedware.net` sowie ein
  A/AAAA-Record `mail.sedware.net` → die öffentliche(n) Gateway-IP(s), dazu
  SPF/DKIM/DMARC, werden über Cloudflare veröffentlicht (außerhalb des Scopes
  dieses Manifests).
