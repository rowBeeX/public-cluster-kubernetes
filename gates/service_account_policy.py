"""Explizite App-ServiceAccounts, die mit der Kubernetes-API arbeiten."""

from __future__ import annotations

API_SERVICE_ACCOUNT_ALLOWLIST = {
    "app-alloy:alloy": "Kubernetes-Discovery und Pod-Log-Erfassung",
    "app-gitlab-runner:gitlab-runner": "Erzeugt Kubernetes-CI-Jobs (Public-Cluster)",
    "app-postgresql:postgres": "CNPG-Instanzmanager",
}
