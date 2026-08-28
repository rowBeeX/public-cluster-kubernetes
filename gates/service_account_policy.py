"""Explizite App-ServiceAccounts, die mit der Kubernetes-API arbeiten."""

from __future__ import annotations

API_SERVICE_ACCOUNT_ALLOWLIST = {
    "app-alloy:alloy": "Kubernetes-Discovery und Pod-Log-Erfassung",
    "app-cnpg-operator:cnpg-operator-cloudnative-pg": "CNPG-Reconciliation",
    "app-cnpg-operator:plugin-barman-cloud": "CNPG-Backup-Reconciliation",
    "app-gitlab-runner:gitlab-runner": "Erzeugt Kubernetes-CI-Jobs (Public-Cluster)",
    "app-gitlab:gitlab-shared-secrets": "Erzeugt interne GitLab-Secrets",
    "app-headlamp:headlamp": "Kubernetes-Clusteroberfläche",
    "app-homepage:homepage": "Kubernetes-Status-Widgets",
    "app-loki:loki": "Rule-Sidecar beobachtet Kubernetes-Secrets",
    "app-monitoring:kube-prometheus-stack-grafana": "Dashboard-Sidecars",
    "app-monitoring:kube-prometheus-stack-kube-state-metrics": "Cluster-Metriken",
    "app-monitoring:kube-prometheus-stack-operator": "Prometheus-Reconciliation",
    "app-monitoring:kube-prometheus-stack-prometheus": "Kubernetes-Discovery",
    "app-monitoring:kube-prometheus-stack-admission": "Webhook-Zertifikat und Patch",
    "app-postgresql:postgres": "CNPG-Instanzmanager",
    "app-stalwart:stalwart-vault": "seed-tls: Stalwart-Neustart nach TLS-Zertifikatswechsel",
    "app-vpa:vpa-admission-controller": "VPA-Admission",
    "app-vpa:vpa-recommender": "VPA-Empfehlungen",
}
