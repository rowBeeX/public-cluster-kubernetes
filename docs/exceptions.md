# Security & Operations Exceptions — public-cluster-kubernetes

Central, reviewable list of deliberate deviations from the hardened default
(baseline PSS, least-privilege, restricted trust, GitOps-declarative). Every
exception has an ID, an owner (team/role, not a person), a reason, the residual
risk, and a review date.

> This file is scoped to `public-cluster-kubernetes`. A repo-spanning
> consolidation is tracked under issue #35.

| ID | Owner | Reason | Risk | Review |
|----|-------|--------|------|--------|
| `EXC-mailedge-baseline-psa` | platform-mail | Postfix master needs uid 0 (privilege-separated design) → namespace `app-mailedge` enforces **baseline**, not restricted. Capabilities are minimized toward restricted (#11): `drop:[ALL]` + only `CHOWN,DAC_OVERRIDE,FOWNER,SETGID,SETUID,NET_BIND_SERVICE,KILL,SYS_CHROOT` added; seccomp RuntimeDefault; `allowPrivilegeEscalation:false`. | Container runs as root; a Postfix RCE would have root in-container, but only the 8 listed caps (no NET_RAW/MKNOD/AUDIT_WRITE/SETFCAP/SETPCAP/FSETID), no host namespaces. | 2026-10-01 |
| `EXC-postfix-writable-rootfs` | platform-mail | `readOnlyRootFilesystem:true` is not achievable for `mail-edge/postfix` (#11/#12): the `boky/postfix` image regenerates `/etc/postfix` at every startup and Postfix writes `/var/lib/postfix/prng_exch`. Listed in the conftest `_rootfs_exceptions` allowlist with the same reason. | Writable image layer inside the container; queue state is on the `mail-edge-spool` PVC, TLS is a read-only mount. | 2026-10-01 |
| `EXC-adguard-privileged-psa` | platform-net | `app-adguard-home` enforces **privileged** PSA because AdGuard runs `hostNetwork:true` to bind host `:53`/`:3000` (DNS + UI over NetBird). Container itself is hardened (drop ALL, only NET_BIND_SERVICE, read-only root fs). | Shares the host network namespace on Host 1; `:53` is firewall-restricted to the private cluster LAN + NetBird (AR-05), not the public internet. | 2026-10-01 |
| `EXC-authentik-baseline-psa` | platform-iam | `app-authentik` enforces **baseline**: the Authentik image needs a writable root filesystem (blueprints/media/cache under the image root), so it cannot meet restricted. Caps are dropped to ALL. | Writable image layer; no added caps, no host namespaces, non-privileged. | 2026-10-01 |
| `EXC-netbird-baseline-psa` | platform-net | `app-netbird` enforces **baseline**: the netbird-dashboard nginx container adds `CHOWN,SETUID,SETGID` (to drop root) and `DAC_OVERRIDE` (log file access) beyond the restricted-allowed NET_BIND_SERVICE. | Extra caps limited to the listed set; drop ALL otherwise, no privileged, no host namespaces. | 2026-10-01 |
