#!/usr/bin/env python3
"""Cluster-Vertrag eines GitOps-Repos auf dem gerenderten Manifest pruefen.

Gemeinsam fuer beide validate.sh; das Repo ist das aktuelle Verzeichnis.
Geprueft wird je Overlay genau einmal gerendert:

* App-Namespaces (``app-<name>``) tragen die vollstaendige
  Pod-Security-Triple und die ``core.sedware.net``-Labels.
* Eine PSA-Abschwaechung (``enforce != restricted``) ist eine bewusste
  Security-Ausnahme und braucht einen Eintrag in ``gates/exceptions.md`` (#11).
* Workloads setzen nur ``resources.requests``. CPU-Limits drosseln auch im
  Leerlauf (CFS), Memory-Limits brauchen einen Eintrag in ``gates/exceptions.md``.
* Jobs tragen die Argo-CD-Hook-Annotation — ohne sie sind sie bei
  Template-Aenderungen unveraenderlich.
* Kein Service exponiert HTTP/HTTPS ueber einen NodePort.

Verwendung:
    python3 gates/manifest_contract.py
"""

from __future__ import annotations

import glob
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

_REQUIRED_NS_LABELS = {
    "pod-security.kubernetes.io/enforce", "pod-security.kubernetes.io/enforce-version",
    "pod-security.kubernetes.io/audit", "pod-security.kubernetes.io/audit-version",
    "pod-security.kubernetes.io/warn", "pod-security.kubernetes.io/warn-version",
    "core.sedware.net/owner", "core.sedware.net/purpose", "app.kubernetes.io/part-of",
}


def _overlays() -> list[str]:
    candidates = sorted(glob.glob("apps/*/")) + sorted(glob.glob("apps/*/resources/"))
    return [c.rstrip("/") for c in candidates if os.path.exists(os.path.join(c, "kustomization.yaml"))]


def check_overlay(overlay: str, exceptions: str) -> list[str]:
    out = subprocess.run(["kubectl", "kustomize", overlay], capture_output=True, text=True, check=False)
    if out.returncode:
        return [f"{overlay}: Kustomize-Rendering fehlgeschlagen"]

    bad: list[str] = []
    for doc in yaml.safe_load_all(out.stdout):
        if not doc:
            continue
        kind, meta = doc.get("kind"), doc.get("metadata", {})
        name = str(meta.get("name", ""))
        if kind == "Namespace" and name.startswith("app-"):
            labels = meta.get("labels") or {}
            missing = _REQUIRED_NS_LABELS - set(labels)
            if missing:
                bad.append(f"{name}: fehlende Namespace-Labels {sorted(missing)}")
            enforce = labels.get("pod-security.kubernetes.io/enforce")
            if enforce and enforce != "restricted" and name not in exceptions:
                bad.append(
                    f"{name}: PSA enforce={enforce} (nicht restricted) ohne Eintrag "
                    "in gates/exceptions.md (#11)"
                )
        if kind in ("Deployment", "StatefulSet", "DaemonSet"):
            pod = doc.get("spec", {}).get("template", {}).get("spec", {})
            for container in pod.get("containers", []) + pod.get("initContainers", []):
                limits = (container.get("resources") or {}).get("limits") or {}
                if "cpu" in limits:
                    bad.append(
                        f"{name}/{container['name']}: resources.limits.cpu gesetzt "
                        "(CFS-Drosselung, ausnahmslos verboten)"
                    )
                for key in sorted(set(limits) - {"cpu"}):
                    # Gleiche Ausnahme wie in render_helm.py: erweiterte
                    # Ressourcen (Device-Plugins, Domäne im Schlüssel) gehen
                    # ausschliesslich als Limit. Beide Prüfer müssen dieselbe
                    # Regel kennen — sonst nimmt der eine an, was der andere
                    # ablehnt, je nachdem ob eine App Helm oder Kustomize nutzt.
                    if "/" in key:
                        continue
                    bad.append(
                        f"{name}/{container['name']}: resources.limits.{key} gesetzt, "
                        "aber nicht in gates/exceptions.md gelistet"
                    )
        if kind == "Job" and "argocd.argoproj.io/hook" not in (meta.get("annotations") or {}):
            bad.append(
                f"{meta.get('namespace')}/{name}: Job ohne Argo-CD-Hook-Annotation "
                "ist bei Template-Aenderungen unveraenderlich"
            )
    return bad


def check_nodeports() -> list[str]:
    bad = []
    for path in Path("apps").rglob("*.yaml"):
        for document in re.split(r"^---\s*$", path.read_text(), flags=re.MULTILINE):
            if not re.search(r"^\s*type:\s*NodePort\s*$", document, re.MULTILINE):
                continue
            if re.search(r"^\s*name:\s*https?\s*$|^\s*port:\s*(80|443)\s*$", document, re.MULTILINE):
                bad.append(f"{path}: HTTP-NodePort gefunden")
    return bad


def main() -> None:
    exceptions = Path("gates/exceptions.md").read_text() if Path("gates/exceptions.md").exists() else ""
    bad = check_nodeports()
    for overlay in _overlays():
        bad += check_overlay(overlay, exceptions)
    if bad:
        print("Verstoss gegen die Cluster-Vertrags-Konvention:", file=sys.stderr)
        for item in bad:
            print("  " + item, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
