#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubevirt-without-fear}"

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

command -v oc >/dev/null 2>&1 || fail "oc is required"
oc whoami >/dev/null 2>&1 || fail "oc is not logged in"
pass "Connected to $(oc whoami --show-server) as $(oc whoami)"

oc api-resources --api-group=kubevirt.io -o name | grep -Eq '^virtualmachines(\.kubevirt\.io)?$' || fail "KubeVirt VirtualMachine API is unavailable"
pass "KubeVirt VirtualMachine API is available"

oc api-resources --api-group=cdi.kubevirt.io -o name | grep -Eq '^datavolumes(\.cdi\.kubevirt\.io)?$' || fail "CDI DataVolume API is unavailable"
pass "CDI DataVolume API is available"

if oc api-resources --api-group=route.openshift.io -o name | grep -Eq '^routes(\.route\.openshift\.io)?$'; then
  pass "OpenShift Route API is available"
else
  warn "Route API not found; use kubectl port-forward in upstream KubeVirt mode"
fi

default_sc="$(oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' | head -n1)"
[[ -n "${default_sc}" ]] || fail "No default StorageClass was found"
pass "Default StorageClass: ${default_sc}"

schedulable_nodes="$(oc get nodes -l kubevirt.io/schedulable=true --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${schedulable_nodes}" -gt 0 ]]; then
  pass "Virtualization-schedulable nodes: ${schedulable_nodes}"
else
  warn "No node has kubevirt.io/schedulable=true; verify OpenShift Virtualization node readiness"
fi

if command -v virtctl >/dev/null 2>&1; then
  pass "virtctl is available for the optional live-migration step"
else
  warn "virtctl is not installed; the core demo still works, but live migration will be skipped"
fi

if oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  warn "Namespace ${NAMESPACE} already exists; deploy.sh will reconcile it"
fi

printf '\nPreflight completed. Review WARN items before presenting.\n'
