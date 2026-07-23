# public-nginx — public internet-facing test server

A minimal static nginx served at **https://public-nginx.dev11.sedware.net** over
the public Envoy edge. It is the single public-edge test app and exists to
demonstrate an ordinary web app reaching the internet end-to-end from the public
cluster.

```
Internet ─▶ public Envoy edge (TLS, *.dev11.sedware.net wildcard cert) ─▶ public-nginx :8080
```

## Why it "just works"

The public `public-dev` Gateway already has an `https` listener for
`*.dev11.sedware.net` with the `public-dev-wildcard-tls` LE certificate, and the
public edge binds the real `:80`/`:443` dual-stack. So no platform change is
needed — only this app plus a DNS record.

## Exposure & security

- `nginxinc/nginx-unprivileged` listens on `:8080` as uid 101 → the namespace
  enforces the **restricted** Pod-Security profile (non-root,
  `readOnlyRootFilesystem`, `drop: [ALL]`; writable dirs are `emptyDir`s).
- `HTTPRoute` attaches to `gateway-system/public-dev` `sectionName: https`.
- CiliumNetworkPolicies: `default-deny` + `allow-edge-ingress` (ingress only from
  the hostNetwork Envoy proxies, seen as `host`/`remote-node`).

## Required outside this repo

**DNS** — `public-nginx` is added to `PUBLIC_EDGE_HOSTS` in
`cluster-testing/{public,local}-cluster/nix/config.py`, so `cloudflare_dns.py`
publishes A/AAAA round-robin to both public hosts. Run `cloudflare_dns.py` +
`cloudflare_dns_verify.py` to apply.

The nginx image is digest-pinned (`nginx-unprivileged:1.31.3-alpine`).
