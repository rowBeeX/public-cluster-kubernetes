# mail-edge — Public Mail Edge / MX Relay

The mandatory public mail entry **and** exit for the self-hosted mail system.
It carries **no user login** (no IMAP/JMAP/ManageSieve/Submission publicly).

```
Inbound:  Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (over NetBird) :25
Outbound: Local Stalwart ─▶ Public Envoy :2525 ─▶ Mail Edge :25 ─▶ Internet :25
```

Direct Internet→Local-Stalwart and direct Local-Stalwart→Internet are forbidden;
this pod is the only path in both directions.

Beide Richtungen sind deklarativ umgesetzt. Internet-MX-Sender dürfen die
SMTP-Session beginnen, können wegen `reject_unauth_destination` aber nur lokale
Empfänger adressieren. Ausgehend erreicht Stalwart über NetBird den privaten
Envoy-Listener `:2525`; dessen TCPRoute endet bei Postfix `:25`.

The edge runs **Postfix** (`boky/postfix`): a fully-declarative, k8s-native SMTP
relay whose entire configuration is env vars (the image applies each
`POSTFIX_<param>` via `postconf`), with no data store and no accounts.

## How the two directions are configured

- **Inbound MX** — `POSTFIX_relay_domains=dev13.sedware.net` accepts mail for the
  domain; `POSTFIX_transport_maps=inline:{ dev13.sedware.net=smtp:[<stalwart>]:25 }`
  forwards it to the Local Stalwart backend (`[...]` = no MX lookup).
- **Outbound relay** — the anti-open-relay boundary is `smtpd_relay_restrictions
  = permit_mynetworks reject_unauth_destination`: relaying to arbitrary
  destinations requires the source to be in `POSTFIX_mynetworks`. That is now
  auf Loopback und das einzelne Server-Node-PodCIDR `10.42.0.0/24` begrenzt.
  Cilium lässt am Backend nur die Host-/Remote-Node-Identity zu; Host 2 liegt
  getrennt in `10.42.1.0/24`. Der frühere
  Wert `100.64.0.0/10` hätte das gesamte NetBird-/CGNAT-Overlay vertraut und ein
  Open-Relay-Risiko erzeugt. The intended relay-client identity is modelled
  declaratively in NetBird (groups `mail-edge` /
  `mail-relay-client` + policy `mail-relay`, provisioned by
  `cluster-testing/.../provision_mail_relay_policy.py`); that policy becomes an
  enforcer once the NetBird least-privilege migration removes `Default All→All`.
- **TLS** — STARTTLS on :25 using the cert-manager `Certificate` `mail-edge-tls`
  (`mail.dev13.sedware.net`, DNS-01 via ClusterIssuer `letsencrypt`). The
  gateway-system wildcard secret is deliberately not reused cross-namespace.

## Exposure & security

- Inbound Service `mail-edge-smtp` uses Cilium Node IPAM on all nodes labelled
  `gateway.sedware.net/enabled=true`. It uses neither deprecated
  `externalIPs` nor LoadBalancer NodePorts and is not routed through Envoy.
- The host firewall permits TCP 25 on the gateway nodes. Node-address changes
  require no application-manifest update.
- Host firewall: TCP 25 is opened on the gateway nodes' LAN/WAN interface in
  `public-cluster-nix` (`roles/public/cluster-server.nix` + `cluster-agent.nix`),
  mirroring the UDP 3478 STUN rule.
- CiliumNetworkPolicies: default-deny; ingress :25 from `world` (MX) + the Local
  Stalwart peer; egress DNS; egress :25 to `world` (delivery) and to the Local
  Stalwart peer (inbound forward). No login ports.
- PSA: namespace enforces **baseline** (audit/warn restricted). Postfix's master
  needs uid 0 (privilege-separated design) so restricted is not achievable; the
  container adds no extra capabilities, uses seccomp RuntimeDefault and disables
  privilege escalation.
- Single replica + RWO PVC `mail-edge-spool` for the queue (deferred mail must
  survive restarts; a Postfix spool cannot be shared across replicas).

## Integration points

- **Local Stalwart backend.** `POSTFIX_transport_maps` forwards `dev13.sedware.net`
  to `smtp:[dev-manager.nb.dev13.sedware.net]:25` — the stable NetBird peer FQDN of
  the Local Private Edge, resolved at delivery time. Outbound relay trust is now
  auf Loopback und das Public-Host-1-PodCIDR begrenzt (`POSTFIX_mynetworks`); siehe
  **Outbound relay** oben.
- **Local Stalwart → Mail Edge reachability.** Stalwart verbindet sich mit
  `public-cluster-host-1.nb.<domain>:2525`. Der Listener ist nur auf `nb-wt0`
  freigegeben und leitet per TCPRoute an diesen Service weiter.
- **DNS.** An MX record `dev13.sedware.net` → `mail.dev13.sedware.net` and an A/AAAA
  record `mail.dev13.sedware.net` → the public gateway IP(s), plus SPF/DKIM/DMARC,
  are published via Cloudflare (out of scope for this manifest).
