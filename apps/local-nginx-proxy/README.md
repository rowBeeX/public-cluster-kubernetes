# local-nginx-proxy — public edge entry for the local cluster's nginx

Publishes **https://local-nginx.dev13.sedware.net** on the public Envoy edge and
re-encrypts it, over NetBird, to the **local** cluster's Envoy edge, which then
routes to the nginx test server (`apps/local-nginx` in `local-cluster-kubernetes`).

```
Internet ─▶ public Envoy edge (TLS, *.dev13.sedware.net wildcard, host local-nginx.dev13)
         ─▶ HTTPRoute URLRewrite Host: local-nginx.local.dev13.sedware.net
         ─▶ Backend local-edge (fqdn dev-manager.nb.dev13.sedware.net:443) + origin TLS
         ─▶ BackendTLSPolicy re-encrypt (verify *.local.dev13 wildcard, System trust)
         ─▶ (NetBird) local Envoy edge :443 ─▶ local HTTPRoute ─▶ local-nginx ClusterIP
```

## Why this shape

The local cluster has **no public NIC** — it is reachable only over LAN/NetBird,
and the public cluster is the only internet edge. To give a *local-cluster*
service a real internet HTTPS URL under `dev13.sedware.net`, the request must enter
at the public edge and be proxied across. This mirrors the **Mail Edge**
(`apps/mail-edge`) public→local pattern, but for HTTPS end-to-end:

- The public `public-dev` Gateway already serves `*.dev13.sedware.net` with the
  wildcard cert, so **no platform change is needed on the public side** — TLS
  terminates at the edge with a valid cert.
- The `HTTPRoute` rewrites the request `Host` to
  `local-nginx.local.dev13.sedware.net` and forwards to an Envoy Gateway `Backend`
  CRD (`local-edge`) whose endpoint is the stable NetBird peer FQDN
  `dev-manager.nb.dev13.sedware.net:443` — the Local Private Edge. CoreDNS resolves
  that FQDN to the current overlay IPv4 at runtime (`*.nb.dev13` forward), so no
  raw per-generation overlay IP, LAN IP or Cilium LB VIP is ever hard-coded.
- A `BackendTLSPolicy` re-encrypts to the local edge and verifies its Let's
  Encrypt `*.local.dev13.sedware.net` wildcard. The rewritten hostname is both the
  SNI presented (selecting the wildcard listener) and the name checked against the
  cert SANs; LE production chains to the publicly trusted ISRG Root X1, so
  `wellKnownCACertificates: System` is enough and no CA bundle is shipped.

This app owns **no pods** — just the `HTTPRoute`, the Envoy Gateway `Backend`, and
the `BackendTLSPolicy`.

## Integration points

- **Upstream peer FQDN** (`Backend` → `dev-manager.nb.dev13.sedware.net:443`). This
  is the stable NetBird peer FQDN of the Local Private Edge (dev-manager); the
  public gateway nodes reach it directly as NetBird peers. No `192.168.100.0/24`
  LAN NetBird route, no `externalIP`, and no local `:8080` firewall opening are
  required.
- **DNS.** `local-nginx` is in `PUBLIC_EDGE_HOSTS` in
  `cluster-testing/{public,local}-cluster/nix/config.py`, so it resolves to the
  public edge (which then proxies to the local cluster); published by
  `cloudflare_dns.py`.
