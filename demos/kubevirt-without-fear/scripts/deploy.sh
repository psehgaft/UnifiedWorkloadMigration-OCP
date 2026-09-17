#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubevirt-without-fear}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${NAMESPACE}" != "kubevirt-without-fear" ]]; then
  printf 'Custom namespace requested: %s\n' "${NAMESPACE}"
  oc kustomize "${ROOT_DIR}/manifests/base" | \
    sed -e "s/name: kubevirt-without-fear/name: ${NAMESPACE}/" \
        -e "s/namespace: kubevirt-without-fear/namespace: ${NAMESPACE}/g" | \
    oc apply -f -
else
  oc apply -k "${ROOT_DIR}/manifests/base"
fi

if oc api-resources --api-group=route.openshift.io -o name | grep -Eq '^routes(\.route\.openshift\.io)?$'; then
  if [[ "${NAMESPACE}" == "kubevirt-without-fear" ]]; then
    oc apply -f "${ROOT_DIR}/manifests/openshift/route.yaml"
  else
    sed "s/namespace: kubevirt-without-fear/namespace: ${NAMESPACE}/g" "${ROOT_DIR}/manifests/openshift/route.yaml" | oc apply -f -
  fi
fi

printf 'Waiting for the VM disk import...\n'
oc -n "${NAMESPACE}" wait --for=condition=Ready datavolume/legacy-api-root --timeout=10m

printf 'Waiting for the VM and frontend...\n'
oc -n "${NAMESPACE}" wait --for=condition=Ready vm/legacy-api --timeout=10m
oc -n "${NAMESPACE}" rollout status deployment/modern-frontend --timeout=5m

if oc -n "${NAMESPACE}" get route modern-frontend >/dev/null 2>&1; then
  host="$(oc -n "${NAMESPACE}" get route modern-frontend -o jsonpath='{.spec.host}')"
  printf '\nDemo URL: https://%s\n' "${host}"
else
  printf '\nUse: oc -n %s port-forward service/modern-frontend 8080:8080\n' "${NAMESPACE}"
fi
