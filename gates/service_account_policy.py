"""Explizite App-ServiceAccounts, die mit der Kubernetes-API arbeiten.

Zwei Leser: `validate.sh` prueft den Render dieses Repos, der Pruefstand
(`cluster-tools`) alle laufenden Pods in `app-*`-Namespaces des oeffentlichen
Clusters. Die Liste ist deshalb die Vereinigung beider — sie enthaelt auch
Identitaeten, die kein Manifest dieses Repos erzeugt. Ein Eintrag ohne
Gegenstueck auf einer der beiden Seiten gehoert geloescht.
"""

from __future__ import annotations

API_SERVICE_ACCOUNT_ALLOWLIST = {
    "app-alloy:alloy": "Kubernetes-Discovery und Pod-Log-Erfassung",
    "app-gitlab-runner:gitlab-runner": "Erzeugt Kubernetes-CI-Jobs (Public-Cluster)",
    "app-postgresql:postgres": "CNPG-Instanzmanager",
    "app-vpa:vpa-recommender": "VPA-Empfehlungen — Plattform aus public-cluster-nix, teilt sich nur das app-*-Praefix",
}
