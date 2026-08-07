# mail-edge — Public Mail Edge / MX Relay

The mandatory public mail entry **and** exit for the self-hosted mail system.
It carries **no user login** (no IMAP/JMAP/ManageSieve/Submission publicly).

```
Inbound:  Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (over NetBird) :25
Outbound: Local Stalwart ─▶ Public Envoy :2525 ─▶ Mail Edge :25 ─▶ Internet :25
```

Direct Internet→Local-Stalwart and direct Local-Stalwart→Internet are forbidden;
this pod is the only path in both directions.

Both directions are implemented declaratively. Internet MX senders may open the
SMTP session but, because of `reject_unauth_destination`, can only address local
recipients. Outbound, Stalwart reaches the private Envoy listener `:2525` over
NetBird; its TCPRoute terminates at Postfix `:25`.

The edge runs **Postfix** (`boky/postfix`): a fully-declarative, k8s-native SMTP
relay whose entire configuration is env vars (the image applies each
`POSTFIX_<param>` via `postconf`), with no data store and no accounts.

## How the two directions are configured

- **Inbound MX** — `POSTFIX_relay_domains=sedware.net` accepts mail for the
  domain; `POSTFIX_transport_maps=inline:{ sedware.net=smtp:[<stalwart>]:25 }`
  forwards it to the Local Stalwart backend (`[...]` = no MX lookup).
- **Outbound relay** — the anti-open-relay boundary is `smtpd_relay_restrictions
  = permit_mynetworks reject_unauth_destination`: relaying to arbitrary
  destinations requires the source to be in `POSTFIX_mynetworks`. That is now
  limited to loopback plus the single server node's Pod CIDR `10.42.0.0/24`.
  Cilium only admits the host/remote-node identity at the backend; a second node
  would sit separately in `10.42.1.0/24`. The former value `100.64.0.0/10` would
  have trusted the entire NetBird/CGNAT overlay and created an open-relay risk.
  The relay-client identity is modelled declaratively in NetBird
  (groups `mail-edge` / `mail-relay-client` + policy `mail-relay`, provisioned by
  `cluster-testing/public-cluster/nix/cluster/provision_mail_relay_policy.py`);
  since the NetBird least-privilege cutover removed `Default All→All`, that
  policy is the enforcing access control for the relay path.
- **TLS** — STARTTLS on :25 using the cert-manager `Certificate` `mail-edge-tls`
  (SANs `mail.sedware.net` and `public-cluster-host-1.nb.sedware.net`, DNS-01 via
  ClusterIssuer `letsencrypt`). The gateway-system wildcard secret is
  deliberately not reused cross-namespace.

## Exposure & security

- Inbound Service `mail-edge-smtp` uses Cilium Node IPAM on all nodes labelled
  `gateway.sedware.net/enabled=true`. It uses neither deprecated
  `externalIPs` nor LoadBalancer NodePorts and is not routed through Envoy.
- Host firewall: TCP 25 is opened on the gateway nodes' internet-facing
  interface in `public-cluster-nix` (`roles/public/gateway-node.nix`), mirroring
  the UDP 3478 STUN rule. Node-address changes require no application-manifest
  update.
- CiliumNetworkPolicies: default-deny; ingress :25 from `world` (MX) and from
  `host`/`remote-node` (the hostNetwork Envoy that carries the private :2525
  relay path); egress DNS; egress :25 to `world` (delivery) and to the NetBird
  overlay CIDR `100.64.0.0/10` (inbound forward to Stalwart). No login ports.
- PSA: namespace enforces **baseline** (audit/warn restricted). Postfix's master
  needs uid 0 (privilege-separated design) so restricted is not achievable; the
  container drops `ALL` and re-adds only the eight capabilities Postfix needs
  (see `docs/exceptions.md`), uses seccomp RuntimeDefault and disables privilege
  escalation.
- Single replica + RWO PVC `mail-edge-spool` for the queue (deferred mail must
  survive restarts; a Postfix spool cannot be shared across replicas).

## Integration points

- **Local Stalwart backend.** `POSTFIX_transport_maps` forwards `sedware.net`
  to `smtp:[beelink-server.nb.sedware.net]:25` — the stable NetBird peer FQDN of
  the Local Private Edge, resolved at delivery time. Outbound relay trust is now
  limited to loopback and the Public Host 1 Pod CIDR (`POSTFIX_mynetworks`); see
  **Outbound relay** above.
- **Local Stalwart → Mail Edge reachability.** Stalwart connects to
  `public-cluster-host-1.nb.sedware.net:2525`. The listener is opened on `nb-wt0`
  only and forwards to this Service via TCPRoute.
- **DNS.** An MX record `sedware.net` → `mail.sedware.net` and an A/AAAA
  record `mail.sedware.net` → the public gateway IP(s), plus SPF/DKIM/DMARC,
  are published via Cloudflare (out of scope for this manifest).
