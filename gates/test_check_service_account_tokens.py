"""Tests für das statische ServiceAccount-Token-Gate."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_service_account_tokens import check


def _workload(*, namespace: str, service_account: str = "default", automount=None):
    pod_spec = {
        "serviceAccountName": service_account,
        "containers": [{"name": "app", "image": "example.invalid/app:test"}],
    }
    if automount is not None:
        pod_spec["automountServiceAccountToken"] = automount
    return {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": "app", "namespace": namespace},
        "spec": {"template": {"spec": pod_spec}},
    }


def _service_account(namespace: str, name: str, automount: bool):
    return {
        "apiVersion": "v1",
        "kind": "ServiceAccount",
        "metadata": {"name": name, "namespace": namespace},
        "automountServiceAccountToken": automount,
    }


class ServiceAccountTokenCheckTest(unittest.TestCase):
    def _check(self, documents: list[dict]) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.yaml"
            path.write_text(yaml.safe_dump_all(documents), encoding="utf-8")
            return check(path)

    def test_rejects_implicit_default_token(self) -> None:
        errors = self._check([_workload(namespace="app-example")])
        self.assertEqual(len(errors), 1)

    def test_accepts_pod_level_opt_out(self) -> None:
        self.assertEqual(
            self._check([_workload(namespace="app-example", automount=False)]), []
        )

    def test_accepts_service_account_opt_out(self) -> None:
        documents = [
            _service_account("app-example", "app", False),
            _workload(namespace="app-example", service_account="app"),
        ]
        self.assertEqual(self._check(documents), [])

    def test_accepts_documented_api_client(self) -> None:
        workload = _workload(namespace="app-headlamp", service_account="headlamp")
        self.assertEqual(self._check([workload]), [])

    def test_namespace_boundary_resets_service_account_state(self) -> None:
        documents = [
            _service_account("app-example", "default", False),
            _workload(namespace="app-example"),
            {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": "app-example"}},
            _workload(namespace="app-example"),
        ]
        self.assertEqual(len(self._check(documents)), 1)


if __name__ == "__main__":
    unittest.main()
