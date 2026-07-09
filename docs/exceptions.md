# Security & Operations Exceptions — public-cluster-kubernetes

Central, reviewable list of deliberate deviations from the hardened default
(baseline PSS, least-privilege, restricted trust, GitOps-declarative). Every
exception has an ID, an owner (team/role, not a person), a reason, the residual
risk, and a review date. Code that relies on an exception references its ID.

> This file is scoped to `public-cluster-kubernetes`. A repo-spanning
> consolidation is tracked under issue #35.

| ID | Owner | Reason | Risk | Review |
|----|-------|--------|------|--------|
| `EXC-mailedge-baseline-psa` | platform-mail | Postfix master needs uid 0 (privilege-separated design) → namespace `app-mailedge` enforces **baseline**, not restricted. No added capabilities, seccomp RuntimeDefault, `allowPrivilegeEscalation:false`. | Container runs as root; a Postfix RCE would have root in-container (but no extra caps, no host namespaces). | 2026-10-01 |
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
