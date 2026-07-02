# mail-edge — Public Mail Edge / MX Relay

The mandatory public mail entry **and** exit for the self-hosted mail system.
It carries **no user login** (no IMAP/JMAP/ManageSieve/Submission publicly).

```
Inbound:  Internet :25 ─▶ Mail Edge ─▶ Local Stalwart (over NetBird) :25
Outbound: Local Stalwart ─▶ Mail Edge (over NetBird) :25 ─▶ Internet :25
```

Direct Internet→Local-Stalwart and direct Local-Stalwart→Internet are forbidden;
this pod is the only path in both directions.

## Implementation choice — Postfix (not Stalwart)

The brief recommended a file-based (ConfigMap-only) Stalwart relay. That is **not
cleanly achievable on Stalwart v0.16.x**: the objects that make Stalwart a relay
— `MtaRoute` (relay/MX routing), the RCPT-stage relay/`allowRelaying` policy and
the local-domain directory — live in Stalwart's **settings/config STORE** and are
provisioned through the web-admin / settings API, not as declarative TOML keys.
The on-disk `--config` file in v0.16 is only a store definition (`{"@type":"RocksDb",...}`),
and Stalwart's only pure-TOML mode is an L7 **mail proxy** (credential-based
reverse proxy for IMAP/SMTP/HTTP), which does not do MX lookups or outbound
internet delivery. A file-only Stalwart relay would therefore still need a data
store + a settings-API seed Job — exactly the non-declarative pattern we are
trying to avoid.

So this app uses **Postfix** (`boky/postfix`), the canonical, fully-declarative
k8s-native SMTP relay. All configuration is expressed as env vars (the image
applies each `POSTFIX_<param>` via `postconf`), no data store and no accounts.

Docs consulted: Stalwart MTA routing / RCPT relay
(`/stalwartlabs/website` — docs/mta/outbound/routing.md, docs/mta/inbound/rcpt.md,
docs/configuration/index.md, docs/migration/proxy/…) and the boky/postfix README
(<https://github.com/bokysan/docker-postfix>).

## How the two directions are configured

- **Inbound MX** — `POSTFIX_relay_domains=dev4.sedware.net` accepts mail for the
  domain; `POSTFIX_transport_maps=inline:{ dev4.sedware.net=smtp:[<stalwart>]:25 }`
  forwards it to the Local Stalwart backend (`[...]` = no MX lookup).
- **Outbound relay** — `POSTFIX_mynetworks` lists **only** the Local Stalwart
  NetBird address (+ loopback), so only that peer may relay to arbitrary
  (internet) destinations; everything else may reach `relay_domains` only. This
  is the anti-open-relay boundary (`smtpd_relay_restrictions =
  permit_mynetworks reject_unauth_destination`, no SASL).
- **TLS** — STARTTLS on :25 using the cert-manager `Certificate` `mail-edge-tls`
  (`mail.dev4.sedware.net`, DNS-01 via ClusterIssuer `letsencrypt-dev`). The
  gateway-system wildcard secret is deliberately not reused cross-namespace.

## Exposure & security

- Inbound Service `mail-edge-smtp` uses `externalIPs: [192.168.101.10,
  192.168.101.11]` (the netbird-stun "no host proxy" pattern), Cilium-announced.
  Not via the Envoy/Cilium Gateway (HTTP-only). On node-IP changes, update the
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

## Placeholders / manual steps an integrator MUST fill in

1. **`REPLACE_ME_LOCAL_STALWART_NETBIRD_IP`** (in `base/resources.yaml`, three
   places: `POSTFIX_transport_maps`, `POSTFIX_mynetworks`, and both the ingress
   and egress `cidr` fields of the `allow-mail-flows` CNP). Set to the Local
   Stalwart pod's NetBird/relay address. Not knowable at manifest time.
2. **Local Stalwart → Mail Edge reachability.** For the outbound direction, the
   Local cluster must be able to dial this pod over NetBird (a NetBird network
   route to the Mail Edge Service/pod). The address the Local Stalwart smarthost
   points at is `REPLACE_ME_MAIL_EDGE_NETBIRD_IP` — see the Local repo
   `apps/stalwart/README.md` (data-store smarthost routing).
3. **Image digest.** Pin `docker.io/boky/postfix:v4.4.0@sha256:…` before merge
   (repo convention). The tag could not be digest-verified offline.
4. **DNS.** Publish an MX record for `dev4.sedware.net` → `mail.dev4.sedware.net`
   and an A record for `mail.dev4.sedware.net` → the public gateway IP(s), plus
   SPF/DKIM/DMARC as appropriate (out of scope for this manifest).
