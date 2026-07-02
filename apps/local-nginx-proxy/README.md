# local-nginx-proxy — public edge entry for the local cluster's nginx

Publishes **https://local-nginx.dev3.sedware.net** on the public Envoy edge and
forwards it, over NetBird, to the nginx test server that runs in the **local**
cluster (`apps/local-nginx` in `local-cluster-kubernetes`).

```
Internet ─▶ public Envoy edge (TLS, *.dev3.sedware.net wildcard)
         ─▶ (NetBird) ─▶ local-nginx Service externalIP 192.168.100.10:8080 ─▶ nginx :8080
```

## Why this shape

The local cluster has **no public NIC** — it is reachable only over LAN/NetBird,
and the public cluster is the only internet edge. To give a *local-cluster*
service a real internet HTTPS URL under `dev3.sedware.net`, the request must enter
at the public edge and be proxied across. This mirrors the **Mail Edge**
(`apps/mail-edge`) public→local pattern, but for HTTP:

- The public `public-dev` Gateway already serves `*.dev3.sedware.net` with the
  wildcard cert, so **no platform change is needed on the public side** — TLS
  terminates at the edge with a valid cert.
- The route's backend is a **selector-less Service** whose endpoints are set by a
  **manual EndpointSlice** pointing at the local cluster over NetBird. This is the
  standard k8s-native way to aim a Gateway `HTTPRoute` at an out-of-cluster
  address. (Alternative: Envoy Gateway's `Backend` CRD with an IP/FQDN endpoint —
  not used here to avoid enabling that API.)

This app owns **no pods** — just the `HTTPRoute`, the selector-less `Service`, and
the `EndpointSlice`.

## Placeholders / manual steps an integrator MUST fill in

1. **Upstream address** (`EndpointSlice` → `192.168.100.10:8080`). Must equal the
   local-nginx `Service` externalIP + port in `local-cluster-kubernetes/apps/local-nginx`.
2. **NetBird route.** The public gateway nodes must have a NetBird route to
   `192.168.100.0/24` so they can reach the local externalIP (same requirement as
   Mail Edge → Local Stalwart). Add it in the NetBird control plane.
3. **Local firewall.** The local manager opens `:8080` on `nb-wt0`
   (see `local-cluster-nix/roles/local/manager.nix`).
4. **DNS.** `local-nginx` is added to `PUBLIC_EDGE_HOSTS` in
   `cluster-testing/{public,local}-cluster/nix/config.py`, so it resolves to the
   public edge (which then proxies to the local cluster). Run `cloudflare_dns.py`.
