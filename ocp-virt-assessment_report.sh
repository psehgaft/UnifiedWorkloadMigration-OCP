#!/bin/bash
# ==============================================================================
# Read-Only Assessment and YAML Manifest Generation Script
# Target: OpenShift 4.21+ / OpenShift Virtualization / MTV
# ==============================================================================

set -u

OUTPUT_DIR="./output"
YAML_DIR="${OUTPUT_DIR}/yamls"
REPORT_FILE="${OUTPUT_DIR}/Assessment_Report.md"
INVENTORY_FILE="./inventory"

# Create directory structure
mkdir -p "${YAML_DIR}"

# Validate active OpenShift session
if ! CURRENT_USER=$(oc whoami 2>/dev/null); then
  echo "Error: No active OpenShift session detected. Please run 'oc login' before continuing."
  exit 1
fi

CLUSTER_SERVER=$(oc whoami --show-server 2>/dev/null)
CURRENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "======================================================================"
echo " Starting read-only assessment on: ${CLUSTER_SERVER}"
echo " Output redirected to: ${OUTPUT_DIR}"
echo "======================================================================"

# ==============================================================================
# 1. GENERATE MARKDOWN REPORT HEADER
# ==============================================================================
cat <<EOF > "${REPORT_FILE}"
# OpenShift Cluster Assessment & Migration Readiness Report

- **Date:** ${CURRENT_DATE}
- **Cluster Server:** \`${CLUSTER_SERVER}\`
- **Evaluated By:** \`${CURRENT_USER}\`
- **Execution Mode:** Read-Only Audit (No changes applied)

---

## Executive Summary of Generated Manifests

All generated YAML manifests have been placed in \`${YAML_DIR}/\`. Review and apply them manually when authorized.

| Component / Resource | Status Detected | Generated Manifest |
| :--- | :--- | :--- |
EOF

# Flag variables to detect missing components
CNV_MISSING=false
MTV_MISSING=false
PROVIDER_MISSING=false

# ==============================================================================
# 2. OPERATOR AND COMPONENT AUDIT
# ==============================================================================

# --- OpenShift Virtualization (CNV) ---
CNV_NS_CHECK=$(oc get namespace openshift-cnv --no-headers 2>/dev/null)
HCO_STATUS=$(oc get hco kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

if [ -z "${CNV_NS_CHECK}" ] \vert{}\vert{} [ "${HCO_STATUS}" != "True" ]; then
  CNV_MISSING=true
  echo "| OpenShift Virtualization | **Missing / Incomplete** | \`yamls/01-cnv-subscription.yaml\`, \`yamls/02-hyperconverged-cr.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| OpenShift Virtualization | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

# --- Migration Toolkit for Virtualization (MTV) ---
MTV_NS_CHECK=$(oc get namespace openshift-mtv --no-headers 2>/dev/null)
FORKLIFT_POD=$(oc get pods -n openshift-mtv -l app=forklift-controller --no-headers 2>/dev/null)

if [ -z "${MTV_NS_CHECK}" ] \vert{}\vert{} [ -z "${FORKLIFT_POD}" ]; then
  MTV_MISSING=true
  echo "| MTV Operator | **Missing / Incomplete** | \`yamls/03-mtv-subscription.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| MTV Operator | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

# --- vCenter Provider ---
PROVIDER_CHECK=$(oc get provider vcenter-provider -n openshift-mtv -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

if [ "${PROVIDER_CHECK}" != "True" ]; then
  PROVIDER_MISSING=true
  echo "| VMware vCenter Provider | **Missing / Not Ready** | \`yamls/04-vcenter-provider-template.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| VMware vCenter Provider | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

echo "---" >> "${REPORT_FILE}"

# ==============================================================================
# 3. QUERIES AND AUDIT DETAILS (ORGANIZED OUTPUTS)
# ==============================================================================

# Helper to append sections to Markdown report
append_section() {
  local title="$1"
  local cmd="$2"
  
  echo -e "\n## ${title}\n" >> "${REPORT_FILE}"
  echo "\`\`\`text" >> "${REPORT_FILE}"
  eval "${cmd}" 2>&1 >> "${REPORT_FILE}"
  echo "\`\`\`" >> "${REPORT_FILE}"
}

echo "Collecting cluster information..."

append_section "1. Cluster Version & Status" "oc get clusterversion"
append_section "2. Cluster Nodes Overview" "oc get nodes -o wide"
append_section "3. Operator CSV Status (All Namespaces)" "oc get csv -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase"

append_section "4. Network Attachment Definitions (NADs)" "oc get net-attach-def -A -o json | jq -r '.items[] | select(.spec.config != null) | .metadata.namespace as \$ns | .metadata.name as \$name | (.spec.config | fromjson?) | \"[\" + \$ns + \"] \" + \$name + \" -> Bridge: \" + (.bridge // \"N/A\")'"

append_section "5. HyperConverged CR Live Migration Config" "oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.spec.liveMigrationConfig}' 2>/dev/null || echo 'HyperConverged CR not found.'"

append_section "6. StorageClasses & Capabilities" "oc get storageclass -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDINGMODE:.volumeBindingMode"

append_section "7. Monitoring PVCs & Alertmanager Pods" "oc get pods -n openshift-monitoring -l app.kubernetes.io/name=alertmanager; echo ''; oc get pvc -n openshift-monitoring | grep -E 'prometheus|alertmanager'"

append_section "8. etcd Backups Status" "oc get cronjob -n etcd-backups 2>/dev/null; echo ''; oc get jobs -n etcd-backups --sort-by=.metadata.creationTimestamp 2>/dev/null"

append_section "9. MachineHealthChecks" "oc get machinehealthcheck -A 2>/dev/null || echo 'No MachineHealthChecks found.'"

append_section "10. Firing Alerts" "oc -n openshift-monitoring exec alertmanager-main-0 -c alertmanager -- amtool --alertmanager.url http://localhost:9093 alert query -a 2>/dev/null || echo 'Unable to query Alertmanager directly.'"

# ==============================================================================
# 4. GENERATE YAMLS FOR MISSING COMPONENTS
# ==============================================================================
echo "Generating YAML manifests for missing components..."

# --- CNV Manifests ---
if [ "${CNV_MISSING}" = true ]; then
  cat <<YAML > "${YAML_DIR}/01-cnv-subscription.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-cnv-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
  - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  channel: stable
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML

  cat <<YAML > "${YAML_DIR}/02-hyperconverged-cr.yaml"
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  liveMigrationConfig:
    bandwidthPerMigration: 64Mi
    completionTimeoutPerGiB: 800
    parallelMigrationsPerCluster: 5
    parallelOutboundMigrationsPerNode: 2
    progressTimeout: 150
YAML
fi

# --- MTV Manifests ---
if [ "${MTV_MISSING}" = true ]; then
  cat <<YAML > "${YAML_DIR}/03-mtv-subscription.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-mtv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-mtv-group
  namespace: openshift-mtv
spec:
  targetNamespaces:
  - openshift-mtv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: mtv-operator
  namespace: openshift-mtv
spec:
  channel: stable
  name: mtv-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML
fi

# --- Provider Manifest ---
if [ "${PROVIDER_MISSING}" = true ]; then
  cat <<YAML > "${YAML_DIR}/04-vcenter-provider-template.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: vcenter-credentials
  namespace: openshift-mtv
type: Opaque
stringData:
  user: "administrator@vsphere.local"
  password: "REPLACE_WITH_ACTUAL_PASSWORD"
  cacert: |
    -----BEGIN CERTIFICATE-----
    REPLACE_WITH_VCENTER_CA_CERTIFICATE
    -----END CERTIFICATE-----
---
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: vcenter-provider
  namespace: openshift-mtv
spec:
  type: vsphere
  url: https://vcenter.yourdomain.com/sdk
  vddkInitImage: quay.io/your-org/vddk:8.0.2
  secret:
    name: vcenter-credentials
    namespace: openshift-mtv
YAML
fi

# ==============================================================================
# 5. GENERATE MAP AND PLAN YAMLS FROM ./inventory
# ==============================================================================
if [ -f "${INVENTORY_FILE}" ]; then
  echo "Processing inventory file '${INVENTORY_FILE}'..."
  
  echo -e "\n## Inventory Processing\n" >> "${REPORT_FILE}"
  echo "Inventory detected. Generating NetworkMaps, StorageMaps, and Migration Plans..." >> "${REPORT_FILE}"

  PLANS=$(awk -F',' '{gsub(/^[" ]+\vert{}[" ]+$/, "", $2); if ($2!="") print $2}' "${INVENTORY_FILE}" | sort -u)

  IFS=$'\n'
  for PLAN in $PLANS; do
    [ -z "${PLAN}" ] && continue
    SLUG=$(echo "${PLAN}" \vert{} tr '[:upper:]' '[:lower:]' \vert{} sed 's/[^a-z0-9]/-/g' \vert{} sed 's/-\+/-/g' \vert{} sed 's/^-//;s/-$//')
    
    # 1. NetworkMap
    cat <<YAML > "${YAML_DIR}/network-map-${SLUG}.yaml"
apiVersion: forklift.konveyor.io/v1beta1
kind: NetworkMap
metadata:
  name: netmap-${SLUG}
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-provider
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    - source:
        name: "VM Network" # Replace with vSphere PortGroup/VLAN
      destination:
        type: pod
        name: target-network
YAML

    # 2. StorageMap
    cat <<YAML > "${YAML_DIR}/storage-map-${SLUG}.yaml"
apiVersion: forklift.konveyor.io/v1beta1
kind: StorageMap
metadata:
  name: storagemap-${SLUG}
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-provider
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    - source:
        name: "datastore-vsphere" # Replace with vSphere Datastore
      destination:
        storageClass: ocs-storagecluster-ceph-rbd # Replace with target StorageClass
YAML

    # 3. Migration Plan
    NETMAP_NAME="netmap-${SLUG}"
    STORAGEMAP_NAME="storagemap-${SLUG}"
    
    PLAN_YAML="${YAML_DIR}/migration-plan-${SLUG}.yaml"
    cat <<YAML > "${PLAN_YAML}"
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: plan-${SLUG}
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vcenter-provider
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    network:
      name: ${NETMAP_NAME}
      namespace: openshift-mtv
    storage:
      name: ${STORAGEMAP_NAME}
      namespace: openshift-mtv
  targetNamespace: openshift-cnv
  warm: true
  vms:
YAML

    awk -F',' -v target_plan="${PLAN}" '
    {
        vm=$1; plan=$2;
        gsub(/^[" ]+|[" ]+$/, "", vm);
        gsub(/^[" ]+|[" ]+$/, "", plan);
        if (plan == target_plan && vm != "") {
            print "    - name: \"" vm "\""
        }
    }' "${INVENTORY_FILE}" >> "${PLAN_YAML}"

    echo "| Wave Plan: ${PLAN} | Generated Mappings & Plan | \`yamls/network-map-${SLUG}.yaml\`, \`yamls/storage-map-${SLUG}.yaml\`, \`yamls/migration-plan-${SLUG}.yaml\` |" >> "${REPORT_FILE}"
  done
else
  echo "Notice: './inventory' file not found. Skipping Migration Plan generation."
fi

# ==============================================================================
# 6. COMPLETION AND SUMMARY
# ==============================================================================
echo "" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "*End of Assessment Report. Generated strictly in read-only mode.*" >> "${REPORT_FILE}"

echo "======================================================================"
echo " Execution completed successfully."
echo " - Markdown report generated at: ${REPORT_FILE}"
echo " - YAML manifests generated at:  ${YAML_DIR}/"
echo "======================================================================"
