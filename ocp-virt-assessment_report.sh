#!/bin/bash
# ==============================================================================
# OpenShift Production Readiness Assessment & Migration Manifest Generator
# Target OpenShift Version: 4.18+
# Execution Mode: Read-Only Audit & YAML Generation (No cluster changes applied)
# Language: English (Documentation, Comments, and Output Logs)
# ==============================================================================

set -u

OUTPUT_DIR="./output"
YAML_DIR="${OUTPUT_DIR}/yamls"
REPORT_FILE="${OUTPUT_DIR}/Assessment_Report.md"
INVENTORY_FILE="./inventory"

# Create required output directories
mkdir -p "${YAML_DIR}"

# Validate active OpenShift session
if ! CURRENT_USER=$(oc whoami 2>/dev/null); then
  echo "Error: No active OpenShift session detected. Please run 'oc login' before proceeding."
  exit 1
fi

CLUSTER_SERVER=$(oc whoami --show-server 2>/dev/null)
CURRENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo "======================================================================"
echo " Starting Integrated Read-Only Assessment"
echo " Cluster API: ${CLUSTER_SERVER}"
echo " Authenticated User: ${CURRENT_USER}"
echo " Timestamp: ${CURRENT_DATE}"
echo " Output Location: ${OUTPUT_DIR}"
echo "======================================================================"

# ==============================================================================
# 1. INITIALIZE MARKDOWN REPORT HEADER & EXECUTIVE SUMMARY
# ==============================================================================
cat <<EOF > "${REPORT_FILE}"
# OpenShift Production Readiness & Migration Assessment Report

- **Date:** ${CURRENT_DATE}
- **Cluster Server:** \`${CLUSTER_SERVER}\`
- **Evaluated By:** \`${CURRENT_USER}\`
- **Execution Mode:** Read-Only Audit & Manifest Generation (No changes applied)

---

## Executive Summary of Generated Manifests

All generated YAML manifests have been placed in \`${YAML_DIR}/\`. Review and apply them manually when authorized.

| Component / Resource | Status Detected | Generated Manifest |
| :--- | :--- | :--- |
EOF

CNV_MISSING=false
MTV_MISSING=false
PROVIDER_MISSING=false

# Audit OpenShift Virtualization (CNV)
CNV_NS_CHECK=$(oc get namespace openshift-cnv --no-headers 2>/dev/null || true)
HCO_STATUS=$(oc get hco kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)

if [ -z "${CNV_NS_CHECK}" ] \vert{}\vert{} [ "${HCO_STATUS}" != "True" ]; then
  CNV_MISSING=true
  echo "| OpenShift Virtualization | **Missing / Incomplete** | \`yamls/01-cnv-subscription.yaml\`, \`yamls/02-hyperconverged-cr.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| OpenShift Virtualization | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

# Audit Migration Toolkit for Virtualization (MTV)
MTV_NS_CHECK=$(oc get namespace openshift-mtv --no-headers 2>/dev/null || true)
FORKLIFT_POD=$(oc get pods -n openshift-mtv -l app=forklift-controller --no-headers 2>/dev/null || true)

if [ -z "${MTV_NS_CHECK}" ] \vert{}\vert{} [ -z "${FORKLIFT_POD}" ]; then
  MTV_MISSING=true
  echo "| MTV Operator | **Missing / Incomplete** | \`yamls/03-mtv-subscription.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| MTV Operator | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

# Audit vCenter Source Provider
PROVIDER_CHECK=$(oc get provider vcenter-provider -n openshift-mtv -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)

if [ "${PROVIDER_CHECK}" != "True" ]; then
  PROVIDER_MISSING=true
  echo "| VMware vCenter Provider | **Missing / Not Ready** | \`yamls/04-vcenter-provider-template.yaml\` |" >> "${REPORT_FILE}"
else
  echo "| VMware vCenter Provider | **Ready** | N/A |" >> "${REPORT_FILE}"
fi

echo "---" >> "${REPORT_FILE}"

# Helper function to append code block sections to the Markdown report
append_section() {
  local title="$1"
  local cmd="$2"
  
  echo -e "\n## ${title}\n" >> "${REPORT_FILE}"
  echo "\`\`\`text" >> "${REPORT_FILE}"
  eval "${cmd}" 2>&1 >> "${REPORT_FILE}" || true
  echo "\`\`\`" >> "${REPORT_FILE}"
}

echo "Executing specialized assessment modules..."

# ==============================================================================
# 2. READ-ONLY AUDIT MODULES & DETAILED QUERY OUTPUTS
# ==============================================================================

# Module 1: Cluster Core Version & Node Overview
append_section "1. Cluster Version & Nodes Overview" "oc get clusterversion; echo ''; oc get nodes -o wide"

# Module 2: All Operator CSVs Status
append_section "2. Operator CSV Status (All Namespaces)" "oc get csv -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase"

# Module 3: Network Attachment Definitions Extraction (extract_nads.sh logic)
append_section "3. Network Attachment Definitions (cnv-bridge)" '
echo "--- Extracting cnv-bridge NADs ---"
oc get NetworkAttachmentDefinition.k8s.cni.cncf.io -A -o json 2>/dev/null | jq -r '\''
  .items[]
  | select(.spec.config != null)
  | (.spec.config | fromjson?)
  | select(.type == "cnv-bridge")
  | "\(.name),\(.bridge)"
'\'' | sort -u || echo "No cnv-bridge NADs found."
'

# Export NADs to CSV file in output directory and /tmp
oc get NetworkAttachmentDefinition.k8s.cni.cncf.io -A -o json 2>/dev/null | jq -r '
  .items[]
  | select(.spec.config != null)
  | (.spec.config | fromjson?)
  | select(.type == "cnv-bridge")
  | "\(.name),\(.bridge)"
' | sort -u > "${OUTPUT_DIR}/cluster-nads-bridge.csv" 2>/dev/null || true
cp "${OUTPUT_DIR}/cluster-nads-bridge.csv" /tmp/cluster-nads-bridge.csv 2>/dev/null || true

# Module 4: Live Migration Network Check (live_migration_check.sh logic)
append_section "4. Live Migration Network Check" '
NS="openshift-cnv"
HC_NAME="kubevirt-hyperconverged"

LM_NET=$(oc get hyperconverged "${HC_NAME}" -n "${NS}" -o yaml 2>/dev/null | yq -r ".spec.liveMigrationConfig.network // \"\"" || true)

if [[ -z "${LM_NET}" \vert{}\vert{} "${LM_NET}" == "null" ]]; then
  echo "FAIL: liveMigrationConfig.network is NOT set on HyperConverged ${HC_NAME} in namespace${NS}"
else
  echo "PASS: liveMigrationConfig.network is set to \"${LM_NET}\""
  if oc get NetworkAttachmentDefinition.k8s.cni.cncf.io "${LM_NET}" -n "${NS}" >/dev/null 2>&1; then
    echo "PASS: NetworkAttachmentDefinition \"${NS}/${LM_NET}\" exists and will be used for live migration"
  else
    echo "FAIL: NetworkAttachmentDefinition \"${NS}/${LM_NET}\" does NOT exist, live migration network is misconfigured"
  fi
fi
'

# Module 5: Alertmanager Configuration, Receivers & Routes (alerts.sh logic)
append_section "5. Alertmanager Configuration, Receivers & Routes" '
oc_exec() {
  local command="$*"
  oc exec alertmanager-main-0 -n openshift-monitoring -- /bin/bash -c "${command}" 2>/dev/null
}

echo "Extracting alertmanager config from cluster secret..."
FULL_CFG=$(oc_exec "amtool config show --alertmanager.url http://localhost:9093" || echo "Unable to query Alertmanager")
ROUTES=$(oc_exec "amtool config routes show --alertmanager.url http://localhost:9093" || echo "Unable to query routes")

RECEIVERS=$(echo "${FULL_CFG}" | awk "/^receivers:/,/^[^[:space:]]/" | awk "/^- name:/ {print \$3}")

if [[ -n "${RECEIVERS}" ]]; then
  echo "PASS: Configured receivers found:"
  echo "${RECEIVERS}"
else
  echo "FAIL: No receivers configured."
fi

echo ""
echo "--- Alertmanager Routes Tree ---"
echo "${ROUTES}"
'

# Module 6: etcd Backup CronJobs & Recent Logs (check_etcd_jobs.sh logic)
append_section "6. etcd Backup CronJobs & Log Retrieval" '
echo "### Looking for etcd-related CronJobs"
cronjobs=$(oc get cronjob -A --no-headers 2>/dev/null | awk "/etcd/ {print \$1\",\"\$2}")

if [[ -z "$cronjobs" ]]; then
  echo "INFO: No CronJobs containing \"etcd\" found in the cluster."
else
  last_job_ns=""
  while IFS="," read -r cron_ns cron_name; do
    [[ -z "$cron_ns" ]] && continue
    echo "CronJob: ${cron_ns}/${cron_name}"
    jobs=$(oc get jobs -n "$cron_ns" --no-headers 2>/dev/null | awk -v cj="$cron_name" "$1 ~ (\"^\*\" cj \"-\") {print \$1}")

    for j in $jobs; do
      succeeded=$(oc -n "$cron_ns" get job "$j" -o jsonpath="{.status.succeeded}" 2>/dev/null || echo "0")
      if [[ "$succeeded" -ge 1 ]]; then
        echo "    PASS - ${cron_ns}/${j} succeeded=${succeeded}"
      else
        echo "    FAIL - ${cron_ns}/${j} succeeded=${succeeded}"
      fi
      last_job_ns="$cron_ns"
    done
  done <<< "$cronjobs"

  if [[ -n "$last_job_ns" ]]; then
    echo ""
    echo "####### Retrieving logs from latest pod in ${last_job_ns}... #####"
    latest_pod=$(oc get pods -n "${last_job_ns}" --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tac | head -n 1 | awk "{print \$1}")
    if [[ -n "$latest_pod" ]]; then
      oc logs -n "${last_job_ns}" "${latest_pod}" | tail -n 25
    else
      echo "No pods found in namespace ${last_job_ns}."
    fi
  fi
fi
'

# Module 7: Loki Logging Infrastructure & Tenant Stream Audit (logging.sh logic)
append_section "7. LokiStack Logging Infrastructure & Tenant Query Audit" '
user=$(oc whoami 2>/dev/null || true)
echo "Logged into OpenShift as: ${user}"
echo "--------------------"
echo -n "Lokistack tuning: "; oc get lokistack/lokistack -n openshift-logging -o jsonpath="{.spec.size}{\"\n\"}" 2>/dev/null || echo "N/A"
echo -n "Logging UI: "; oc get UIPlugin/logging -o json 2>/dev/null | jq -r ".status.conditions[] | select(.type==\"Available\" and .reason==\"UIPluginAvailable\") | .status" || echo "N/A"
echo -n "CLF outputs: "; oc get ClusterLogForwarder -n openshift-logging -o json 2>/dev/null | jq -c "[.items[] | .spec.outputs[]|.type]" || echo "N/A"

echo ""
echo "--- Querying Loki for logs for each tenant type ---"
TOKEN=$(oc whoami -t 2>/dev/null || true)
HOST=$(oc get routes/lokistack -n openshift-logging -o jsonpath="{.spec.host}" 2>/dev/null || true)

if [[ -n "$HOST" && -n "$TOKEN" ]]; then
  for t in application audit infrastructure; do
    echo -n "${t} logs (5m count): "
    curl -sH "Authorization: Bearer ${TOKEN}" \
      "https://${HOST}/api/logs/v1/${t}/loki/api/v1/query" \
      --data-urlencode "query=count_over_time({log_type=\"${t}\"}[5m])" 2>/dev/null \
      | jq "if .status then .data.stats.summary.totalEntriesReturned else \"Error: query failed\" end" || echo "Failed"
  done
else
  echo "LokiStack route or bearer token unavailable for live query."
fi
'

# Module 8: Monitoring PVC Capacity & Retention Formula Check (monitoring_pvc.sh logic)
append_section "8. Monitoring Storage & PVC Retention Capacity Check" '
echo "### Checking Core Monitoring PVC Existence"
for pvc in {alertmanager-main-db-alertmanager-main,prometheus-k8s-db-prometheus-k8s}-{0,1}; do
  if oc get "pvc/${pvc}" -n openshift-monitoring &>/dev/null; then
    echo "PASS - openshift-monitoring/${pvc}"
  else
    echo "FAIL - openshift-monitoring/${pvc} missing"
  fi
done

echo ""
echo "### Checking Prometheus PVC Retention vs Capacity (10GiB/day)"
RET_VAL=$(oc -n openshift-monitoring get configmap cluster-monitoring-config -o json 2>/dev/null | jq -r ".data[\"config.yaml\"] // \"\"" | yq ".prometheusK8s.retention" 2>/dev/null || true)
DAYS=15
if [[ "$RET_VAL" =~ ^([0-9]+)d$ ]]; then DAYS="${BASH_REMATCH[1]}"; fi
REQ_GI=$(( DAYS * 10 ))

for pvc in prometheus-k8s-db-prometheus-k8s-{0,1}; do
  RAW_SIZE=$(oc -n openshift-monitoring get pvc "$pvc" -o jsonpath="{.status.capacity.storage}" 2>/dev/null || true)
  NUM=$(echo "$RAW_SIZE" | sed -E "s/([0-9]+).*/\1/")
  UNIT=$(echo "$RAW_SIZE" | sed -E "s/[0-9]+(.*)/\1/")
  PVC_GI=$NUM
  if [[ "$UNIT" == "Ti" ]]; then PVC_GI=$(( NUM * 1024 )); fi
  
  if [[ -n "$PVC_GI" && $PVC_GI -ge$REQ_GI ]]; then
    echo "PASS - openshift-monitoring/${pvc} size=${PVC_GI}Gi, retention=${DAYS}d (required >=${REQ_GI}Gi)"
  else
    echo "FAIL/WARN - openshift-monitoring/${pvc} size=${PVC_GI:-0}Gi, retention=${DAYS}d (required >=${REQ_GI}Gi)"
  fi
done
'

# Module 9: MachineHealthCheck & MachineSet Verification (mhc.sh logic)
append_section "9. MachineHealthCheck & MachineSet Label Verification" '
echo "Checking for machinehealthcheck/worker-metal:"
oc describe machinehealthcheck worker-metal -n openshift-machine-api 2>/dev/null | grep -A7 "^Spec:" || echo "No MHC worker-metal found."

echo ""
echo -n "Verifying MachineSet selector match: "
MHC_MS=$(oc get machinehealthcheck worker-metal -n openshift-machine-api -o jsonpath="{.spec.selector.matchLabels.machine\.openshift\.io/cluster-api-machineset}" 2>/dev/null || true)
ACTUAL_MS=$(oc get machinesets -n openshift-machine-api -o jsonpath="{..metadata.name}" 2>/dev/null || true)

if [[ -n "$MHC_MS" && "$MHC_MS" == "$ACTUAL_MS" ]]; then
  echo "Pass (Matches: ${MHC_MS})"
else
  echo "Fail (MHC MachineSet: \"${MHC_MS:-none}\", Cluster MachineSets: \"${ACTUAL_MS:-none}\")"
fi
'

# Module 10: StorageClasses Summary
append_section "10. StorageClasses & Provisioners Capability Overview" "oc get storageclass -o custom-columns=NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM:.reclaimPolicy,BINDINGMODE:.volumeBindingMode"

# ==============================================================================
# 3. MANIFEST GENERATION FOR MISSING COMPONENTS & VALIDATION TEMPLATES
# ==============================================================================
echo "Generating missing infrastructure manifests and test templates inside ${YAML_DIR}/..."

# OpenShift Virtualization (CNV) Manifests
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

# Migration Toolkit for Virtualization (MTV) Manifests
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

# VMware vCenter Source Provider Manifest Template
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

# Virtual Machine Fedora Validation Template (fedora-pr-val-*.yaml)
cat <<YAML > "${YAML_DIR}/05-fedora-validation-vm.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: pr-validation-test
  labels:
    app: pr-validation
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: fedora-pr-val-root
  namespace: pr-validation-test
  annotations:
    cdi.kubevirt.io/storage.usePopulator: "false"
spec:
  sourceRef:
    kind: DataSource
    name: fedora
    namespace: openshift-virtualization-os-images
  storage:
    storageClassName: nfs-csi
    accessModes:
    - ReadWriteMany
    resources:
      requests:
        storage: 30Gi
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: fedora-pr-val
  namespace: pr-validation-test
  labels:
    app: pr-validation
spec:
  runStrategy: Always
  instancetype:
    kind: virtualmachineclusterinstancetype
    name: u1.medium
  preference:
    kind: virtualmachineclusterpreference
    name: fedora
  template:
    spec:
      domain:
        devices: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: fedora-pr-val-root
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: fedora
            chpasswd:
              expire: false
YAML

# ==============================================================================
# 4. MAPS & PLAN MANIFEST GENERATION FROM ./inventory
# ==============================================================================
if [ -f "${INVENTORY_FILE}" ]; then
  echo "Processing inventory file '${INVENTORY_FILE}'..."
  echo -e "\n## Migration Inventory Processing\n" >> "${REPORT_FILE}"

  PLANS=$(awk -F',' '{gsub(/^[" ]+\vert{}[" ]+$/, "", $2); if ($2!="") print $2}' "${INVENTORY_FILE}" | sort -u)

  IFS=$'\n'
  for PLAN in $PLANS; do
    [ -z "${PLAN}" ] && continue
    SLUG=$(echo "${PLAN}" \vert{} tr '[:upper:]' '[:lower:]' \vert{} sed 's/[^a-z0-9]/-/g' \vert{} sed 's/-\+/-/g' \vert{} sed 's/^-//;s/-$//')
    
    # 1. NetworkMap Manifest
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
        name: "VM Network" # Source vSphere Distributed PortGroup or VLAN
      destination:
        type: pod
        name: target-network
YAML

    # 2. StorageMap Manifest
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
        name: "datastore-vsphere" # Source vSphere Datastore
      destination:
        storageClass: ocs-storagecluster-ceph-rbd # Target StorageClass
YAML

    # 3. Migration Plan Manifest
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
# 5. COMPLETION SUMMARY
# ==============================================================================
echo "" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "*End of Integrated Assessment Report. Generated strictly in read-only mode.*" >> "${REPORT_FILE}"

echo "======================================================================"
echo " Assessment completed successfully."
echo " - Report Markdown: ${REPORT_FILE}"
echo " - Manifests Dir:   ${YAML_DIR}/"
echo " - NADs Export:     ${OUTPUT_DIR}/cluster-nads-bridge.csv & /tmp/cluster-nads-bridge.csv"
echo "======================================================================"
