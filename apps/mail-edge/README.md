# mail-edge — Public Mail Edge / MX Relay

The mandatory public mail entry **and** exit for the self-hosted mail system.
It carries **no user login** (no IMAP/JMAP/ManageSieve/Submission publicly).

```
Inbound:  Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (over NetBird) :25
Outbound: Local Stalwart ─▶ Mail Edge (over NetBird) :25 ─▶ Internet :25
```

Direct Internet→Local-Stalwart and direct Local-Stalwart→Internet are forbidden;
this pod is the only path in both directions.

> **Status:** both mail flows are currently **not yet functional** and carry no
> traffic. Cilium does not serve `:25` on the NetBird `wt0` interface, so the
> Local Stalwart cannot reach this edge over the overlay; and `boky/postfix`'s
> default `smtpd_client_restrictions=permit_mynetworks,reject` makes `mynetworks`
> a *connect* gate, so a world MX sender is refused at connect too. Making the
> paths live is a NetBird-routing task tracked in
> [`docs/exceptions.md`](../../docs/exceptions.md) (`EXC-mail-relay-path`). This
> README documents the intended design; the relay **trust** has already been
> hardened (see below).

The edge runs **Postfix** (`boky/postfix`): a fully-declarative, k8s-native SMTP
relay whose entire configuration is env vars (the image applies each
`POSTFIX_<param>` via `postconf`), with no data store and no accounts.

## How the two directions are configured

- **Inbound MX** — `POSTFIX_relay_domains=dev6.sedware.net` accepts mail for the
  domain; `POSTFIX_transport_maps=inline:{ dev6.sedware.net=smtp:[<stalwart>]:25 }`
  forwards it to the Local Stalwart backend (`[...]` = no MX lookup).
- **Outbound relay** — the anti-open-relay boundary is `smtpd_relay_restrictions
  = permit_mynetworks reject_unauth_destination`: relaying to arbitrary
  destinations requires the source to be in `POSTFIX_mynetworks`. That is now
  **loopback-only** (`127.0.0.0/8 [::1]/128`) — **no external peer is trusted**
  (issue #2/#3). The former value `100.64.0.0/10` trusted the *entire*
  NetBird/CGNAT overlay (any peer), an open-relay risk. When the overlay path is
  built (see Status above), add the relay client's exact overlay `/32` here
  (resolved live from NetBird), never a broad range. The intended relay client's
  identity is modelled declaratively in NetBird (groups `mail-edge` /
  `mail-relay-client` + policy `mail-relay`, provisioned by
  `cluster-testing/.../provision_mail_relay_policy.py`); that policy becomes an
  enforcer once the NetBird least-privilege migration removes `Default All→All`.
- **TLS** — STARTTLS on :25 using the cert-manager `Certificate` `mail-edge-tls`
  (`mail.dev6.sedware.net`, DNS-01 via ClusterIssuer `letsencrypt-dev`). The
  gateway-system wildcard secret is deliberately not reused cross-namespace.

## Exposure & security

- Inbound Service `mail-edge-smtp` uses `externalIPs: [192.168.101.10,
  192.168.101.11]` (the netbird-stun "no host proxy" pattern), Cilium-announced.
  Not via the Envoy Gateway (which is HTTP-only). On node-IP changes, update the
  Service and the firewall rule in `public-cluster-nix`.
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

- **Local Stalwart backend.** `POSTFIX_transport_maps` forwards `dev6.sedware.net`
  to `smtp:[dev-manager.nb.dev6.sedware.net]:25` — the stable NetBird peer FQDN of
  the Local Private Edge, resolved at delivery time. Outbound relay trust is now
  loopback-only (`POSTFIX_mynetworks`); see **Outbound relay** above.
- **Local Stalwart → Mail Edge reachability.** For the outbound direction the Local
  cluster dials this pod over NetBird; the Local Stalwart smarthost points at this
  edge — see the Local repo `apps/stalwart/README.md`.
- **DNS.** An MX record `dev6.sedware.net` → `mail.dev6.sedware.net` and an A/AAAA
  record `mail.dev6.sedware.net` → the public gateway IP(s), plus SPF/DKIM/DMARC,
  are published via Cloudflare (out of scope for this manifest).
