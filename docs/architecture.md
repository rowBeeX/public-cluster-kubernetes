# Public Dev application architecture

Cloudflare round-robin DNS maps `*.dev2.sedware.net` to both public nodes.
Cilium's host-network Gateway listens on 80/443, terminates the Dev wildcard
certificate issued by cert-manager and forwards accepted HTTPRoutes to
ClusterIP services. No HAProxy, Traefik, HTTP NodePort or Kubernetes Ingress is
in this path.

The control plane is intentionally not highly available:
`public-cluster-host-1` is the k3s server and `public-cluster-host-2` is an
agent. Both are Gateway and workload nodes. Cilium provides CNI, kube-proxy
replacement, Gateway API, service load balancing and policy enforcement.

AdGuard DNS and NetBird STUN are non-HTTP protocols exposed by explicit Cilium
Services. Authentik, AdGuard's UI and NetBird's HTTP/gRPC endpoints attach to
the shared public Dev Gateway.

All namespaces use CiliumNetworkPolicy. CrowdSec agents send decisions to the
central local LAPI over NetBird; node firewall bouncers and the public
CiliumCIDRGroup enforce those decisions locally.

Only Dev domains are active. Production hostnames are not rendered or routed.
