# shellcheck shell=bash
# Gemeinsame Strukturvalidierung und Policy-as-Code für beide validate.sh (#17).
# kubeconform übernimmt die Schema-Validierung einschließlich CRDs aus dem
# datreeio-Katalog; conftest prüft die OPA-/Rego-Security-Policies aus
# policy/*.rego. Beide laufen in gepinnten Podman-Images, sodass keine
# Hostinstallation nötig ist und die Versionen reproduzierbar bleiben.
# Regex-Prüfungen in validate.sh bleiben einfachen Leak-/String-Regeln vorbehalten.

_KUBELINT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KUBECONFORM_IMAGE="${KUBECONFORM_IMAGE:-ghcr.io/yannh/kubeconform:v0.8.0@sha256:5103f6f5e89061728aad4ad5a250627dd0fc9b2a92eb876f3762677a4222f9e0}"
_CONFTEST_IMAGE="${CONFTEST_IMAGE:-docker.io/openpolicyagent/conftest:v0.69.0@sha256:23f0bcddf2c6a30be11d00c7867c2f087277d669ce544639093857d294bf6c22}"
_POLICY_DIR="$_KUBELINT_DIR/policy"

# kube_lint <combined-rendered.yaml> -> 0 bei Erfolg, 1 bei Fehlschlag.
kube_lint() {
  local rendered="$1" rc=0
  # Fehlschlagen statt überspringen: ein stiller Erfolg ohne Prüfung ist die
  # gefährlichere Antwort — das Gate hieße dann grün, ohne etwas gesehen zu haben.
  if ! command -v podman >/dev/null 2>&1; then
    printf 'kube_lint: podman fehlt — Schema- und Policy-Prüfung nicht möglich\n' >&2
    return 1
  fi

  printf 'kubeconform (Schema-Validierung)…\n'
  if ! podman run --rm -i "$_KUBECONFORM_IMAGE" \
      -strict -ignore-missing-schemas -summary \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/52b0261318acc7dd0b66e032759b1f218216b980/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
      - < "$rendered"; then
    printf 'kubeconform: Schema-Validierung fehlgeschlagen\n' >&2
    rc=1
  fi

  printf 'conftest (Security-Policies)…\n'
  if ! podman run --rm -i -v "$_POLICY_DIR":/policy:ro "$_CONFTEST_IMAGE" \
      test --policy /policy --no-color -; then
    printf 'conftest: Policy-Verstoß\n' >&2
    rc=1
  fi < "$rendered"

  return "$rc"
}
