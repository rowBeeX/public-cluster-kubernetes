# mail-edge — Public Mail Edge / MX Relay

The mandatory public mail entry **and** exit for the self-hosted mail system.
It carries **no user login** (no IMAP/JMAP/ManageSieve/Submission publicly).

```
Inbound:  Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (over NetBird) :25
Outbound: Local Stalwart ─▶ Mail Edge (over NetBird) :25 ─▶ Internet :25
```

Direct Internet→Local-Stalwart and direct Local-Stalwart→Internet are forbidden;
this pod is the only path in both directions.

The edge runs **Postfix** (`boky/postfix`): a fully-declarative, k8s-native SMTP
relay whose entire configuration is env vars (the image applies each
`POSTFIX_<param>` via `postconf`), with no data store and no accounts.

## How the two directions are configured

- **Inbound MX** — `POSTFIX_relay_domains=dev5.sedware.net` accepts mail for the
  domain; `POSTFIX_transport_maps=inline:{ dev5.sedware.net=smtp:[<stalwart>]:25 }`
  forwards it to the Local Stalwart backend (`[...]` = no MX lookup).
- **Outbound relay** — `POSTFIX_mynetworks` lists **only** the Local Stalwart
  NetBird address (+ loopback), so only that peer may relay to arbitrary
  (internet) destinations; everything else may reach `relay_domains` only. This
  is the anti-open-relay boundary (`smtpd_relay_restrictions =
  permit_mynetworks reject_unauth_destination`, no SASL).
- **TLS** — STARTTLS on :25 using the cert-manager `Certificate` `mail-edge-tls`
  (`mail.dev5.sedware.net`, DNS-01 via ClusterIssuer `letsencrypt-dev`). The
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

- **Local Stalwart backend.** `POSTFIX_transport_maps` forwards `dev5.sedware.net`
  to `smtp:[dev-manager.nb.dev5.sedware.net]:25` — the stable NetBird peer FQDN of
  the Local Private Edge, resolved at delivery time. Outbound relay is allowed only
  from the NetBird CGNAT range `100.64.0.0/10` (`POSTFIX_mynetworks`), so only the
  Local Stalwart peer may relay to arbitrary destinations.
- **Local Stalwart → Mail Edge reachability.** For the outbound direction the Local
  cluster dials this pod over NetBird; the Local Stalwart smarthost points at this
  edge — see the Local repo `apps/stalwart/README.md`.
- **DNS.** An MX record `dev5.sedware.net` → `mail.dev5.sedware.net` and an A/AAAA
  record `mail.dev5.sedware.net` → the public gateway IP(s), plus SPF/DKIM/DMARC,
  are published via Cloudflare (out of scope for this manifest).
