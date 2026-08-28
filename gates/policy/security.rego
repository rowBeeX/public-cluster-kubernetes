# Security-Policies als Code (Issue #17), ausgewertet auf dem gerenderten
# GitOps-Output. Strukturelle Regeln stehen hier, einfache String- und
# Leak-Prüfungen bleiben in validate.sh.
package main

import rego.v1

_workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"}

_containers(obj) := cs if {
	spec := obj.spec.template.spec
	cs := array.concat(
		object.get(spec, "containers", []),
		object.get(spec, "initContainers", []),
	)
}

# Container-Images müssen unveränderlich per Digest gepinnt sein — ausnahmslos.
deny contains msg if {
	input.kind in _workload_kinds
	some c in _containers(input)
	not contains(c.image, "@sha256:")
	msg := sprintf("%s/%s: image %q is not digest-pinned (@sha256:)", [input.kind, input.metadata.name, c.image])
}

# Privilegierte Container sind verboten.
deny contains msg if {
	input.kind in _workload_kinds
	some c in _containers(input)
	c.securityContext.privileged == true
	msg := sprintf("%s/%s: privileged container %q", [input.kind, input.metadata.name, c.name])
}

# Schreibbare Root-Dateisysteme sind nur als bewusste, dokumentierte Ausnahme
# zulässig (#12). Schlüssel für eigene Workloads: "<Workload>/<Container>".
_rootfs_exceptions := {
	# Drittanbieter-Images ohne unterstützte Read-only-Option. Dauerhafte Daten
	# liegen auf PVCs; betroffen ist nur die flüchtige Container-Schicht.
	"couchdb/couchdb": "CouchDB/Erlang writes runtime state under the image root",
	"borgwarehouse/borgwarehouse": "Next.js server + sshd write to the image root; repos are on PVC",
	"headlamp/headlamp": "Headlamp writes plugin/cache state under the image root",
	"homepage/homepage": "Homepage writes its rendered config/cache under the image root",
	# Public Cluster: Postfix-Master läuft konzeptbedingt als root und erzeugt
	# /etc/postfix beim Start neu; Capabilities sind stattdessen minimiert.
	"mail-edge/postfix": "root Postfix master + boky regenerates /etc/postfix at startup (#11)",
	"adguard-home/bootstrap-config": "AdGuard bootstrap writes its generated config at startup",
	"authentik-server/authentik": "Authentik writes blueprints/media/cache under the image root",
	"authentik-worker/authentik": "Authentik worker writes cache/tmp under the image root",
	"netbird-dashboard/dashboard": "nginx-based dashboard writes its templated config at startup",
}

# Offizielle Helm-Charts, deren unterstützte Laufzeit schreibbare Pfade im
# Image benötigt. Die Ausnahme ist absichtlich auf Namespace und exakten
# Workload-Namen beziehungsweise GitLab-Präfix begrenzt; eigene Bootstrap-Jobs
# im selben Namespace fallen nicht darunter. Begründungen: gates/exceptions.md.
_helm_rootfs_exception(obj) if {
	obj.metadata.namespace == "app-alloy"
	obj.metadata.name == "alloy"
}

_helm_rootfs_exception(obj) if {
	obj.metadata.namespace == "app-gitlab"
	startswith(obj.metadata.name, "gitlab-")
}

_helm_rootfs_exception(obj) if {
	obj.metadata.namespace == "app-immich"
	obj.metadata.name in {"immich-server", "immich-machine-learning"}
}

_helm_rootfs_exception(obj) if {
	obj.metadata.namespace == "app-monitoring"
	obj.metadata.name == "kube-prometheus-stack-grafana"
}

_helm_rootfs_exception(obj) if {
	obj.metadata.name == "nextcloud"
	startswith(obj.metadata.labels["helm.sh/chart"], "nextcloud-")
}

_helm_rootfs_exception(obj) if {
	obj.metadata.namespace == "app-vaultwarden"
	obj.metadata.name == "vaultwarden"
}

deny contains msg if {
	input.kind in _workload_kinds
	some c in _containers(input)
	not c.securityContext.readOnlyRootFilesystem == true
	key := sprintf("%s/%s", [input.metadata.name, c.name])
	not _rootfs_exceptions[key]
	not _helm_rootfs_exception(input)
	msg := sprintf("%s/%s: container %q has a writable root filesystem — set readOnlyRootFilesystem: true or add a documented exception (#12)", [input.kind, input.metadata.name, c.name])
}

# App-Namespaces tragen das vollständige Pod-Security-Triple.
deny contains msg if {
	input.kind == "Namespace"
	startswith(input.metadata.name, "app-")
	some label in {
		"pod-security.kubernetes.io/enforce",
		"pod-security.kubernetes.io/audit",
		"pod-security.kubernetes.io/warn",
	}
	not input.metadata.labels[label]
	msg := sprintf("Namespace %s is missing Pod-Security label %s", [input.metadata.name, label])
}
