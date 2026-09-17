#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubevirt-without-fear}"
DEMO_AUTO="${DEMO_AUTO:-0}"

pause() {
  if [[ "${DEMO_AUTO}" != "1" ]]; then
    read -r -p $'\nPress Enter to continue... '
  fi
}

banner() { printf '\n\033[1;35m=== %s ===\033[0m\n' "$1"; }

call_app() {
  oc -n "${NAMESPACE}" exec deploy/modern-frontend -- \
    python3 -c 'import urllib.request; print(urllib.request.urlopen("http://modern-frontend:8080/api", timeout=5).read().decode())'
}

banner "1. One control plane: inventory both runtimes and their dependencies"
oc -n "${NAMESPACE}" get vm,vmi,dv,pvc,deploy,pod,svc,route -o wide 2>/dev/null || \
  oc -n "${NAMESPACE}" get vm,vmi,dv,pvc,deploy,pod,svc -o wide
pause

banner "2. One application: a container calls the VM through Kubernetes DNS"
call_app
pause

banner "3. Workload-aware objects: VM desired state and runtime instance"
oc -n "${NAMESPACE}" get vm legacy-api -o custom-columns='VM:.metadata.name,DESIRED:.spec.runStrategy,READY:.status.ready,STATUS:.status.printableStatus'
oc -n "${NAMESPACE}" get vmi legacy-api -o custom-columns='VMI:.metadata.name,UID:.metadata.uid,NODE:.status.nodeName,PHASE:.status.phase'
old_uid="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.metadata.uid}')"
pause

banner "4. Reconciliation: remove the VMI and let the VM controller recover it"
oc -n "${NAMESPACE}" delete vmi legacy-api --wait=false
printf 'Waiting for a replacement VMI with a new UID...\n'
for _ in $(seq 1 120); do
  new_uid="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
  ready="$(oc -n "${NAMESPACE}" get vm legacy-api -o jsonpath='{.status.ready}' 2>/dev/null || true)"
  if [[ -n "${new_uid}" && "${new_uid}" != "${old_uid}" && "${ready}" == "true" ]]; then
    break
  fi
  sleep 5
done
[[ -n "${new_uid:-}" && "${new_uid}" != "${old_uid}" ]] || { echo "Replacement VMI did not become ready" >&2; exit 1; }
printf 'Old VMI UID: %s\nNew VMI UID: %s\n' "${old_uid}" "${new_uid}"
call_app
printf 'The persistent_request_count continued because the VM boot disk is a persistent DataVolume.\n'
pause

banner "5. Optional mobility: migrate only if the platform reports eligibility"
live_status="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{range .status.conditions[?(@.type=="LiveMigratable")]}{.status}{end}' 2>/dev/null || true)"
if command -v virtctl >/dev/null 2>&1 && [[ "${live_status}" == "True" ]]; then
  source_node="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.status.nodeName}')"
  virtctl -n "${NAMESPACE}" migrate legacy-api
  printf 'Migration requested from node %s. Waiting for completion...\n' "${source_node}"
  for _ in $(seq 1 120); do
    completed="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.status.migrationState.completed}' 2>/dev/null || true)"
    failed="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.status.migrationState.failed}' 2>/dev/null || true)"
    [[ "${completed}" == "true" || "${failed}" == "true" ]] && break
    sleep 5
  done
  target_node="$(oc -n "${NAMESPACE}" get vmi legacy-api -o jsonpath='{.status.nodeName}')"
  oc -n "${NAMESPACE}" get virtualmachineinstancemigration
  printf 'Source node: %s\nCurrent node: %s\n' "${source_node}" "${target_node}"
else
  printf 'Skipped: virtctl is unavailable or the VMI does not report LiveMigratable=True.\n'
  printf 'This is an intentional lesson: common APIs do not remove storage, device, or topology constraints.\n'
fi

banner "Conclusion"
printf '%s\n' \
  'The cluster deployed, connected, observed, and recovered a VM and containers through one declarative control plane.' \
  'The platform unified operations while still exposing the VM-specific requirements that matter.'
