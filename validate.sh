#!/usr/bin/env bash
set -euo pipefail

# Das public-cluster-kubernetes-Repo ermitteln; Env-Override für abweichende Layouts.
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${PUBLIC_CLUSTER_KUBERNETES_ROOT:-}" ]]; then
  repo="$(cd "$PUBLIC_CLUSTER_KUBERNETES_ROOT" && pwd)"
else
  repo="$_script_dir"
fi
cd "$repo"

command -v kubectl >/dev/null 2>&1 || {
  printf 'kubectl wird für das Kustomize-Rendering benötigt\n' >&2
  exit 1
}

failed=0
source "$_script_dir/gates/kube-lint.sh"
source "$_script_dir/gates/manifest-gates.sh"

# Alle Apps rendern und den Gesamt-Output strukturell (kubeconform) sowie gegen
# die Security-Policies (conftest) prüfen (#17).
combined="$(mktemp)"
for app in apps/*/; do
  [[ -f "$app/kustomization.yaml" ]] || continue
  app="${app%/}"
  printf 'render %s\n' "$app"
  rendered="$(mktemp)"
  if ! kubectl kustomize "$app" >"$rendered"; then
    failed=1
  else
    cat "$rendered" >> "$combined"; printf '\n---\n' >> "$combined"
    gate_rendered "$rendered" "$app" || failed=1
  fi
  rm -f "$rendered"
done
python3 "$_script_dir/gates/check_service_account_tokens.py" \
  "$combined" || failed=1
kube_lint "$combined" || failed=1
rm -f "$combined"

gate_sources || failed=1
python3 "$_script_dir/gates/manifest_contract.py" || failed=1

# #29: CI-Builds laufen rootless. Der Runner-Executor muss das ausdruecklich
# erklaeren -- ein fehlender Schluessel waere zwar per Default sicher, aber
# nicht nachweisbar.
rg -q 'allow_privilege_escalation[[:space:]]*=[[:space:]]*false' apps/gitlab-runner || {
  printf 'gitlab-runner: allow_privilege_escalation = false fehlt in der config.toml (#29)\n' >&2
  failed=1
}

if rg -n --glob '!*.md' \
  '(password|token|secret)[[:space:]]*:[[:space:]]*[^{$<[:space:]]' apps; then
  printf 'möglicher Klartext-Secret-Marker gefunden\n' >&2
  failed=1
fi

# Anti-Open-Relay-Gate (Issue #2/#3): ein Postfix `mynetworks` darf außer dem
# Loopback keine breiten Netze vertrauen. `100.64.0.0/10` (gesamtes NetBird/
# CGNAT-Overlay) oder ein IPv4-CIDR < /24 wären ein Open-Relay-Risiko.
if python3 - <<'PY'
import glob, ipaddress, re, sys
loopback = {ipaddress.ip_network("127.0.0.0/8"), ipaddress.ip_network("::1/128")}
bad = []
for path in glob.glob("apps/**/*.yaml", recursive=True):
    lines = open(path).read().splitlines()
    for i, line in enumerate(lines):
        if "POSTFIX_mynetworks" not in line:
            continue
        blob = line + " " + (lines[i + 1] if i + 1 < len(lines) else "")
        m = re.search(r'value:\s*["\']?([^"\'\n]+)', blob)
        for tok in (m.group(1) if m else "").replace("[", "").replace("]", "").split():
            try:
                net = ipaddress.ip_network(tok, strict=False)
            except ValueError:
                continue
            if net in loopback:
                continue
            if (net.version == 4 and net.prefixlen < 24) or (net.version == 6 and net.prefixlen < 112):
                bad.append(f"{path}: POSTFIX_mynetworks vertraut zu breitem Netz {tok}")
if bad:
    print("Mail-Relay mynetworks zu breit (Issue #2/#3):", file=sys.stderr)
    for b in bad:
        print("  " + b, file=sys.stderr)
    sys.exit(1)
PY
then :; else failed=1; fi

# #7: Direkte L4-Node-Exposition verwendet ausschließlich Cilium Node IPAM.
# Kubernetes 1.36 deprecatet Service externalIPs. Der Node-IPAM-Controller
# übernimmt die Gateway-Node-Adressen dynamisch; NodePorts bleiben deaktiviert.
if python3 - <<'PY'
import glob
import os
import subprocess
import sys

import yaml

expected = {
    ("app-netbird", "netbird-stun"),
    ("app-mailedge", "mail-edge-smtp"),
}
expected_selector = "gateway.sedware.net/enabled=true"
# Abweichungen vom Cluster-Default, jeweils mit Grund. Siehe die Prüfung unten.
policy_by_service = {
    ("app-mailedge", "mail-edge-smtp"): "Local",
    ("app-netbird", "netbird-stun"): "Local",
}
# netbird-server ist ein Stateful-Singleton auf lokalem Host-1-Storage
# (WaitForFirstConsumer) und kann nicht auf jeden Gateway-Node gespiegelt
# werden — die volle Knotenabdeckung, die Local sonst verlangt, ist hier
# strukturell unerreichbar. Trotzdem ist Local richtig: STUN beantwortet die
# Frage "welche Adresse siehst du von mir" — eine falsche Antwort (Cluster-
# SNAT liefert eine Pod-IP statt der Client-IP) ist schlimmer als keine. Der
# Knoten ohne lokalen Endpoint bleibt fuer STUN bewusst stumm.
spread_exempt = {("app-netbird", "netbird-stun")}
bad = []
spread_required = set()
workloads = {}

found = set()
for app in sorted(glob.glob("apps/*/")):
    if not os.path.exists(os.path.join(app, "kustomization.yaml")):
        continue
    out = subprocess.run(
        ["kubectl", "kustomize", app],
        capture_output=True,
        text=True,
    )
    if out.returncode:
        bad.append(f"{app}: Kustomize-Rendering fehlgeschlagen")
        continue
    rendered = [d for d in yaml.safe_load_all(out.stdout) if d]
    for doc in rendered:
        if doc.get("kind") in ("Deployment", "StatefulSet", "DaemonSet"):
            md = doc.get("metadata", {})
            workloads[(md.get("namespace"), md.get("name"))] = doc
    for doc in rendered:
        if doc.get("kind") != "Service":
            continue
        metadata = doc.get("metadata", {})
        spec = doc.get("spec", {})
        service = (metadata.get("namespace"), metadata.get("name"))
        if spec.get("externalIPs"):
            bad.append(f"{service}: veraltetes spec.externalIPs")
        if spec.get("type") != "LoadBalancer":
            continue
        found.add(service)
        if service not in expected:
            bad.append(f"{service}: undokumentierter LoadBalancer")
        if spec.get("loadBalancerClass") != "io.cilium/node":
            bad.append(f"{service}: loadBalancerClass muss io.cilium/node sein")
        if spec.get("allocateLoadBalancerNodePorts") is not False:
            bad.append(f"{service}: LoadBalancer-NodePorts müssen deaktiviert sein")
        # Cluster ist der Default. Local ist NUR erlaubt, wenn der dahinter
        # liegende Workload auf JEDEM Node läuft, den der IPAM-Selektor trifft —
        # sonst verschluckt ein Node ohne lokalen Endpoint den Verkehr
        # stillschweigend. Umgekehrt ist Local dort Pflicht, wo die Client-IP
        # Teil der Autorisierung ist: beim Mail-Edge entscheidet Postfix anhand
        # der Quelladresse über das Relay, und das SNAT der Cluster-Policy machte
        # aus jedem Internet-Absender einen vertrauenswürdigen (offenes Relay,
        # live nachgewiesen).
        want_policy = policy_by_service.get(service, "Cluster")
        if spec.get("externalTrafficPolicy") != want_policy:
            bad.append(
                f"{service}: externalTrafficPolicy muss {want_policy} sein "
                f"(ist {spec.get('externalTrafficPolicy')!r})"
            )
        if want_policy == "Local":
            spread_required.add(service)
        selector = (metadata.get("annotations") or {}).get(
            "io.cilium.nodeipam/match-node-labels"
        )
        if selector != expected_selector:
            bad.append(f"{service}: unerwarteter Node-IPAM-Selector {selector!r}")
        if any("nodePort" in port for port in spec.get("ports", [])):
            bad.append(f"{service}: expliziter nodePort ist verboten")

if found != expected:
    bad.append(f"Node-IPAM-Services {sorted(found)!r}, erwartet {sorted(expected)!r}")

# Fuer Local-Services muss der Workload nachweislich auf jedem Gateway-Node
# landen. Ohne diesen Nachweis waere Local ein stiller Schwarzlochfehler: der
# Node ohne lokalen Endpoint nimmt die Verbindung an und verwirft sie.
selector_label, _, selector_value = expected_selector.partition("=")
for ns, svc in sorted(spread_required - spread_exempt):
    wl = workloads.get((ns, svc.removesuffix("-smtp")))
    if wl is None:
        # Service- und Workload-Name muessen nicht uebereinstimmen; ueber den
        # Selector suchen.
        for (wns, _wname), cand in workloads.items():
            if wns != ns:
                continue
            wl = cand
            break
    if wl is None:
        bad.append(f"({ns!r}, {svc!r}): Local, aber kein Workload im Namespace gefunden")
        continue
    pod = wl["spec"]["template"]["spec"]
    if (pod.get("nodeSelector") or {}).get(selector_label) != selector_value:
        bad.append(
            f"({ns!r}, {svc!r}): Local verlangt nodeSelector "
            f"{selector_label}={selector_value} am Workload"
        )
    anti = (
        (pod.get("affinity") or {})
        .get("podAntiAffinity", {})
        .get("requiredDuringSchedulingIgnoredDuringExecution", [])
    )
    if not any(t.get("topologyKey") == "kubernetes.io/hostname" for t in anti):
        bad.append(
            f"({ns!r}, {svc!r}): Local verlangt harte podAntiAffinity auf "
            "kubernetes.io/hostname, damit je Node genau ein Endpoint entsteht"
        )

if bad:
    print("Verstoß gegen den Cilium-Node-IPAM-Service-Vertrag (#7):", file=sys.stderr)
    for item in bad:
        print("  " + item, file=sys.stderr)
    sys.exit(1)
PY
then :; else failed=1; fi

# #37: einheitliches App-Layout — keine Monolith-Datei. Eine Manifest-Datei, die
# einen Namespace definiert, darf keine Workloads/Policies enthalten (Namespace-
# Gerüst gehört in namespace.yaml, siehe apps/README.md).
if python3 - <<'PY'
import glob, re, sys
bad = []
mix = re.compile(r'^kind:\s*(Deployment|StatefulSet|DaemonSet|CiliumNetworkPolicy|CiliumClusterwideNetworkPolicy|NetworkPolicy)\s*$', re.M)
for path in glob.glob("apps/*/*.yaml") + glob.glob("apps/*/resources/*.yaml"):
    text = open(path).read()
    if re.search(r'^kind:\s*Namespace\s*$', text, re.M) and mix.search(text):
        bad.append(path)
if bad:
    print("Monolith-Manifest (Namespace + Workload/Policy in einer Datei, #37):", file=sys.stderr)
    for b in bad:
        print("  " + b + " — in namespace.yaml / workload.yaml / networkpolicy.yaml aufteilen", file=sys.stderr)
    sys.exit(1)
PY
then :; else failed=1; fi

# Semantische Prüfung kritischer Env-Werte: ein erfolgreiches Render beweist
# nicht, dass der richtige Eintrag gesetzt wurde.
# Deployment/Container/Env werden hier eindeutig über ihre NAMEN adressiert.
if python3 - <<'PY'
import subprocess, sys, yaml

expected = {
    ("mail-edge", "mail-edge", "postfix"): {
        "POSTFIX_myhostname": "mail.sedware.net",
        "POSTFIX_relay_domains": "sedware.net",
        "POSTFIX_transport_maps": "inline:{ sedware.net=smtp:[beelink-server.nb.sedware.net]:25 }",
    },
}
bad = []
for (app, deploy, container), want in expected.items():
    app_dir = f"apps/{app}"
    out = subprocess.run(["kubectl", "kustomize", app_dir], capture_output=True, text=True)
    if out.returncode:
        bad.append(f"{app_dir}: Kustomize-Rendering fehlgeschlagen")
        continue
    env = None
    # Deployment ODER StatefulSet: der Mail-Edge ist ein StatefulSet, weil jeder
    # Gateway-Node einen eigenen Postfix-Spool braucht (siehe die
    # externalTrafficPolicy-Prüfung oben).
    for doc in yaml.safe_load_all(out.stdout):
        if not doc or doc.get("kind") not in ("Deployment", "StatefulSet"):
            continue
        if doc.get("metadata", {}).get("name") != deploy:
            continue
        for c in doc["spec"]["template"]["spec"].get("containers", []):
            if c.get("name") == container:
                env = {e["name"]: e.get("value") for e in c.get("env", [])}
    if env is None:
        bad.append(f"{app_dir}: Workload {deploy}/Container {container} nicht gefunden")
        continue
    for name, value in want.items():
        if name not in env:
            bad.append(f"{deploy}/{container}: env {name} fehlt im Render")
        elif env[name] != value:
            bad.append(f"{deploy}/{container}: env {name}={env[name]!r}, erwartet {value!r}")
if bad:
    print("kritische Env-Werte falsch oder fehlend:", file=sys.stderr)
    for b in bad:
        print("  " + b, file=sys.stderr)
    sys.exit(1)
PY
then :; else failed=1; fi

exit "$failed"
