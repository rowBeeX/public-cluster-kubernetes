# shellcheck shell=bash
# Gemeinsame Regex-Gates beider validate.sh. Hier stehen ausschließlich
# einfache Leak-/String-Regeln; der Cluster-Vertrag (Namespace-Labels, PSA,
# Limits, Jobs, NodePorts) liegt in gates/manifest_contract.py, Schema und
# Policies in gates/kube-lint.sh.
#
# Vendorte Charts sind ueberall ausgenommen: sie tragen Upstream-Templates
# ({{ .Values… }} statt Images) und Upstream-Defaults.

# gate_rendered <rendered.yaml> <label> — Pruefungen auf EINEM gerenderten Overlay.
gate_rendered() {
  local rendered="$1" label="$2" rc=0 hits
  # Jedes gerenderte Image trägt einen sichtbaren Tag UND einen
  # unveraenderlichen sha256-Digest.
  hits="$(rg -o '^\s*image:\s*\S+' "$rendered" \
    | rg -v ':[^/@[:space:]]+@sha256:[0-9a-f]{64}$' || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n%s: gerendertes Image ohne sichtbaren Tag und sha256-Digest\n' "$hits" "$label" >&2
    rc=1
  fi
  # Es gibt nur eine Umgebung. Der dev<N>-Teil des Regex verlangt eine Ziffer;
  # die Hostnamen der entfernten Dev-Nodes haben keine und wuerden sonst
  # durchrutschen (die Local-Nodes heissen beelink-server/fujitsu-server).
  hits="$(rg -o '[A-Za-z0-9_.-]*dev[0-9]+\.sedware\.net|dev-(manager|worker)' "$rendered" || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n%s: Dev-Rest im gerenderten Manifest — die Dev-Umgebung ist entfernt\n' "$hits" "$label" >&2
    rc=1
  fi
  return "$rc"
}

# gate_sources — Quelldatei-Gates; das GitOps-Repo ist das aktuelle Verzeichnis.
gate_sources() {
  local rc=0 hits

  hits="$(rg -n --glob '*.yaml' --glob '!**/vendor/**' \
    '^[[:space:]]*kind:[[:space:]]*(Ingress|NetworkPolicy|IngressRoute|IngressRouteTCP|Middleware)[[:space:]]*$|traefik\.io/' \
    apps || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\nLegacy-Ingress-, Policy- oder Traefik-Ressource gefunden\n' "$hits" >&2
    rc=1
  fi

  if rg -n --glob '!**/vendor/**' --pcre2 '^\s*image:\s*(?![a-z0-9.-]+/)[^[:space:]]+' apps; then
    printf 'unqualifiziertes Container-Image gefunden (Registry fehlt)\n' >&2
    rc=1
  fi

  hits="$(rg -n --glob '!**/vendor/**' '^\s*image:' apps | rg -v 'image:[[:space:]]*$' \
    | rg -v ':[^/@[:space:]]+@sha256:[0-9a-f]{64}$' || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\nContainer-Image ohne unveraenderlichen sha256-Digest gefunden\n' "$hits" >&2
    rc=1
  fi

  if rg -n --glob '*.yaml' --glob '*.yaml.in' --glob '!**/vendor/**' \
      'core\.sedware\.net/owner:[[:space:]]*(tobias|[a-z0-9._%+-]+@)' apps; then
    printf 'persoenlicher owner-Marker gefunden — team-/rollenbasiert verwenden\n' >&2
    rc=1
  fi

  rg -q 'kind:[[:space:]]*CiliumNetworkPolicy' apps || {
    printf 'keine CiliumNetworkPolicy gefunden\n' >&2
    rc=1
  }
  rg -q 'kind:[[:space:]]*(HTTPRoute|GRPCRoute)' apps || {
    printf 'keine Gateway-API-Route gefunden\n' >&2
    rc=1
  }

  return "$rc"
}
