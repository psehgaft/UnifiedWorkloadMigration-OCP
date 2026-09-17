#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kubevirt-without-fear}"
printf 'Deleting demo namespace %s and all resources in it...\n' "${NAMESPACE}"
oc delete namespace "${NAMESPACE}"
