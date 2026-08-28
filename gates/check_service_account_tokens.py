#!/usr/bin/env python3
"""Automatische Kubernetes-API-Tokens in gerenderten App-Workloads prüfen."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml


from service_account_policy import API_SERVICE_ACCOUNT_ALLOWLIST

_DIRECT_WORKLOADS = {"DaemonSet", "Deployment", "Job", "StatefulSet"}


def _pod_spec(document: dict) -> dict | None:
    kind = document.get("kind")
    spec = document.get("spec") or {}
    if kind in _DIRECT_WORKLOADS:
        return (spec.get("template") or {}).get("spec") or {}
    if kind == "CronJob":
        job = (spec.get("jobTemplate") or {}).get("spec") or {}
        return (job.get("template") or {}).get("spec") or {}
    return None


def check(path: Path) -> list[str]:
    documents = [
        document
        for document in yaml.safe_load_all(path.read_text(encoding="utf-8"))
        if isinstance(document, dict)
    ]
    tokenless_accounts: set[tuple[str, str]] = set()
    errors: list[str] = []
    for document in documents:
        metadata = document.get("metadata") or {}
        namespace = metadata.get("namespace", "default")
        if document.get("kind") == "Namespace" and metadata.get("name", "").startswith(
            "app-"
        ):
            namespace = metadata["name"]
            tokenless_accounts = {
                identity for identity in tokenless_accounts if identity[0] != namespace
            }
            continue
        if document.get("kind") == "ServiceAccount":
            identity = (namespace, metadata.get("name"))
            if document.get("automountServiceAccountToken") is False:
                tokenless_accounts.add(identity)
            else:
                tokenless_accounts.discard(identity)
            continue

        pod_spec = _pod_spec(document)
        if pod_spec is None:
            continue
        if not namespace.startswith("app-"):
            continue
        service_account = pod_spec.get("serviceAccountName", "default")
        identity = f"{namespace}:{service_account}"
        if pod_spec.get("automountServiceAccountToken") is False:
            continue
        if (namespace, service_account) in tokenless_accounts:
            continue
        if identity in API_SERVICE_ACCOUNT_ALLOWLIST:
            continue
        errors.append(
            f"{document.get('kind')}/{namespace}/{metadata.get('name')}: "
            f"automatischer Kubernetes-API-Token für {identity}"
        )
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    errors = check(args.manifest)
    if errors:
        print("unerlaubte automatische App-ServiceAccount-Tokens:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
