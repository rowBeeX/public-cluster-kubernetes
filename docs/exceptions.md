# Security & Operations Exceptions — public-cluster-kubernetes

Central, reviewable list of deliberate deviations from the hardened default
(baseline PSS, least-privilege, restricted trust, GitOps-declarative). Every
exception has an ID, an owner (team/role, not a person), a reason, the residual
risk, and a review date. Code that relies on an exception references its ID.

> This file is scoped to `public-cluster-kubernetes`. A repo-spanning
> consolidation is tracked under issue #35.

| ID | Owner | Reason | Risk | Review |
|----|-------|--------|------|--------|
| `EXC-mailedge-baseline-psa` | platform-mail | Postfix master needs uid 0 (privilege-separated design) → namespace `app-mailedge` enforces **baseline**, not restricted. Capabilities are minimized toward restricted (#11): `drop:[ALL]` + only `CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID,NET_BIND_SERVICE,KILL,SYS_CHROOT` added; seccomp RuntimeDefault; `allowPrivilegeEscalation:false`. | Container runs as root; a Postfix RCE would have root in-container, but only the 8 listed caps (no NET_RAW/MKNOD/AUDIT_WRITE/SETFCAP/SETPCAP/FSETID), no host namespaces. | 2026-10-01 |
| `EXC-postfix-writable-rootfs` | platform-mail | `readOnlyRootFilesystem:true` is not achievable for `mail-edge/postfix` (#11/#12): the `boky/postfix` image regenerates `/etc/postfix` at every startup and Postfix writes `/var/lib/postfix/prng_exch`. Listed in the conftest `_rootfs_exceptions` allowlist with the same reason. | Writable image layer inside the container; queue state is on the `mail-edge-spool` PVC, TLS is a read-only mount. | 2026-10-01 |
| `EXC-adguard-privileged-psa` | platform-net | `app-adguard-home` enforces **privileged** PSA because AdGuard runs `hostNetwork:true` to bind host `:53`/`:3000` (DNS + UI over NetBird). Container itself is hardened (drop ALL, only NET_BIND_SERVICE, read-only root fs). | Shares the host network namespace on Host 1; `:53` is firewall-restricted to the private cluster LAN + NetBird (AR-05), not the public internet. | 2026-10-01 |
| `EXC-authentik-baseline-psa` | platform-iam | `app-authentik` enforces **baseline**: the Authentik image needs a writable root filesystem (blueprints/media/cache under the image root), so it cannot meet restricted. Caps are dropped to ALL. | Writable image layer; no added caps, no host namespaces, non-privileged. | 2026-10-01 |
| `EXC-netbird-baseline-psa` | platform-net | `app-netbird` enforces **baseline**: the netbird-dashboard nginx container adds `CHOWN,SETUID,SETGID` (to drop root) and `DAC_OVERRIDE` (log file access) beyond the restricted-allowed NET_BIND_SERVICE. | Extra caps limited to the listed set; drop ALL otherwise, no privileged, no host namespaces. | 2026-10-01 |
| `EXC-mail-relay-path` | platform-mail | The mail-edge inbound-MX and outbound-relay data paths are **not yet functional**: Cilium does not serve `:25` on the NetBird `wt0` interface (verified: overlay-IP-in-externalIPs and NetBird subnet routes to the externalIP both get connection-refused), and `boky/postfix`'s default `smtpd_client_restrictions=permit_mynetworks,reject` makes `mynetworks` a connect gate. | No mail flows today (0 messages). Making it live needs a cluster-wide Cilium change (serve services on `wt0`) or a forwarder — done under the NetBird routing work (#19/#24), where the positive end-to-end relay test also lands. | 2026-10-01 |

## Notes

### `EXC-mail-relay-path` — relay trust is already hardened

Independent of the (tracked) path work, the relay **trust** is hardened now
(issue #2/#3):

- `POSTFIX_mynetworks` is **loopback-only** (`127.0.0.0/8 [::1]/128`) — the
  former `100.64.0.0/10` trusted the entire NetBird/CGNAT overlay (open-relay
  risk). Enforced by the `validate.sh` guard (no `POSTFIX_mynetworks` CIDR
  broader than `/24` outside loopback).
- The Cilium `:25` relay-ingress is scoped to the NetBird pool `100.82.0.0/16`
  (documentary; peers appear as `world` to Cilium).
- The intended relay-client identity is modelled declaratively in NetBird
  (groups `mail-edge` / `mail-relay-client` + policy `mail-relay`, provisioned
  idempotently by
  `cluster-testing/public-cluster/nix/dev-install/provision_mail_relay_policy.py`).
  It is **not enforcing** while the NetBird `Default All→All` policy exists; it
  becomes the enforcer under the least-privilege migration (#24).
- Negative test: `cluster-testing` area `mail-relay`
  (`smoke_mail_relay.py`) asserts `mynetworks` is loopback-only, that
  `smtpd_relay_restrictions` ends in `reject_unauth_destination`, and that a
  non-trusted source is refused (`5xx`).

### `EXC-mail-relay-path` — outbound path: proven-pattern implementation plan

The **inbound** path already works (Internet → mail-edge `:25` → local Stalwart
over NetBird). The blocker for **outbound** (local Stalwart → mail-edge → Internet)
was that Cilium does not serve a Service on the NetBird `wt0` interface. But the
*local* cluster edge already serves `:25` over NetBird via an Envoy Gateway TCP
listener + TCPRoute (`local-cluster-nix .../gateway/00-local-gateway.yaml.in`,
`mail-smtp`). The same **proven pattern** applies on the public edge, so the
outbound path is implementable — it just changes the internet-facing mail edge and
therefore needs a maintenance window with end-to-end verification (and ideally
out-of-band recovery), not a blind live sync.

Concrete design (additive to the working inbound path):

1. **Public edge listener** — add a TCP listener (e.g. `:2525`, avoids the
   internet `:25` externalIP) on the `public-dev` Gateway + a `TCPRoute` to the
   `mail-edge` Postfix, mirroring the local edge's `mail-smtp` listener. Restrict
   it to the NetBird overlay via the host firewall (`nb-wt0` only).
2. **Postfix trust** — add the *edge forward source* `/32` (a single, fixed local
   address — **not** a broad overlay range) to `POSTFIX_mynetworks`, so only the
   edge path may relay. Keep `reject_unauth_destination`.
3. **Stalwart** — set the relayhost to the public edge overlay name `:2525`.
4. **Verify** — send a test message to an external MX and confirm delivery; the
   `mail-relay` smoke gains a positive end-to-end assertion alongside the existing
   negative one.

Until that window, outbound relay is intentionally inactive; dev outbound-to-
internet is low value and the security-relevant relay **trust** hardening (#2/#3)
is already done and tested. Tied to the NetBird least-privilege migration
(`local-cluster-nix/docs/security/accepted-risks.md` AR-06) and #24.
