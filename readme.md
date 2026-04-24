# VMware to OpenShift Virtualization with MTV
## CRD inventory, 1000-VM execution model, and step-by-step runbook

> Scope: Standard VMware vSphere -> OpenShift Virtualization migration using Red Hat Migration Toolkit for Virtualization (MTV / Forklift).
> Version note: This document is aligned to the current Red Hat 2.11 planning/migration documentation plus CLI examples documented in 2.6/2.11. Always validate fields against the exact MTV release installed in your cluster.

---

## 1) CRDs directly used in a VMware -> OpenShift Virtualization migration

### A. MTV / Forklift CRDs authored by the migration team

| Kind | API group | Purpose | When you use it |
|---|---|---|---|
| `ForkliftController` | `forklift.konveyor.io/v1beta1` | Operator configuration CR that deploys and tunes MTV components. | Once, during installation and tuning. |
| `Provider` | `forklift.konveyor.io/v1beta1` | Defines a source or destination provider connection. | Required for VMware source and OpenShift Virtualization destination. |
| `Host` | `forklift.konveyor.io/v1beta1` | Associates an ESXi host moRef with the VMware migration network IP. | Used for VMware migrations that require explicit host transfer-network configuration. |
| `NetworkMap` | `forklift.konveyor.io/v1beta1` | Maps source port groups / networks to target pod or Multus networks. | Required per migration plan, even if empty. |
| `StorageMap` | `forklift.konveyor.io/v1beta1` | Maps VMware datastores to target OpenShift storage classes. | Required per migration plan, even if empty. |
| `Hook` | `forklift.konveyor.io/v1beta1` | Optional pre/post Ansible hook executed during the plan lifecycle. | Optional for pre-checks, cloud-init, or guest reconfiguration. |
| `Plan` | `forklift.konveyor.io/v1beta1` | Declares the VM set, network map, storage map, migration type, and target namespace. | One plan per wave/batch. |
| `Migration` | `forklift.konveyor.io/v1beta1` | Executes a Plan and tracks progress/status. | One or more executions per plan. |

### B. CRDs generated/consumed during execution (not authored manually in most VMware migrations)

| Kind | API group | Owner/component | Why it appears |
|---|---|---|---|
| `DataVolume` | `cdi.kubevirt.io` | CDI / MTV | Created for VMware disk transfer workflows. |
| `VirtualMachine` | `kubevirt.io` | MTV / OpenShift Virtualization | Created once the disks are ready and the migrated VM definition is materialized. |
| `VirtualMachineInstance` | `kubevirt.io` | KubeVirt | Appears when the migrated VM is started. |

### C. Important resources you will see that are **not CRDs**
These are still essential, but they are **standard Kubernetes resources**, not CRDs:

- `Secret`
- `PersistentVolumeClaim`
- `Pod` (for example `conversion`, `importer`, `pvcinit`, `virt-launcher`)
- `Job` (optional, when hooks run)
- `ConfigMap`
- `NetworkAttachmentDefinition` (CRD from Multus, not from MTV, but often required)
- `StorageClass`
- `Namespace`

---

## 2) Live-cluster commands to verify the CRDs

```bash
oc get crd | grep forklift
oc api-resources --api-group=forklift.konveyor.io -o wide
oc get forkliftcontroller -A
oc get providers,hosts,networkmaps,storagemaps,hooks,plans,migrations -A
```

If you also want to see runtime objects created by CDI/KubeVirt:

```bash
oc get datavolumes,pvc,virtualmachines,virtualmachineinstances -A
```

---

## 3) Hard constraints that shape the 1000-VM example

1. A VMware migration plan cannot contain more than **500 VMs or 500 disks**.
2. Warm migration is supported for VMware, but requires VMware Changed Block Tracking (CBT).
3. Cold migration is the default migration type.
4. Do not place in the same plan VMs that rely on guest-initiated iSCSI or NFS mounts without additional planning.
5. Network and storage maps should be created reusable/ownerless when you expect to reuse them across many plans.
6. Use a dedicated transfer network whenever possible.

---

## 4) Recommended execution model for 1000 VMs

Because a single plan cannot exceed 500 VMs/500 disks, **1000 VMs must be split across multiple plans**. In practice, I recommend smaller waves than the hard maximum.

### Recommended structure
- **10 waves of 100 VMs each**
- 1 `Plan` CR per wave
- 1 `Migration` CR per execution
- Dedicated target namespace per wave
- Shared reusable `NetworkMap` and `StorageMap` patterns
- Separate warm/cold strategy by workload class
- Pilot first, then progressive expansion

### Example rollout
- Wave 0: 10 pilot VMs
- Wave 1: 50 low-risk VMs
- Waves 2-4: 100 VMs each
- Waves 5-10: 100–150 VMs each, adjusted by disk count and risk

### Why not just two plans of 500?
Because the product limit is not the same as the operationally safe batch size. Ten waves of 100 VMs each give you:
- faster blast-radius control
- easier rollback/triage
- cleaner cutover windows
- cleaner ownership alignment
- better storage and network saturation control

---

## 5) Step-by-step runbook

### Step 1. Prepare the target platform
Validate:
- OpenShift Virtualization installed and healthy
- CDI healthy
- destination storage classes validated
- Multus / target networks validated
- adequate compute, memory, and storage headroom
- DNS, NTP, routes, firewall, and load balancer dependencies reviewed

Recommended checks:

```bash
oc get clusterversion
oc get co
oc get pods -n openshift-cnv
oc get pods -n openshift-cnv | egrep 'cdi|virt'
oc get storageclass
oc get network-attachment-definitions -A
```

### Step 2. Install and configure MTV
Install the MTV Operator and create the `ForkliftController` CR.

Recommended checks:

```bash
oc get pods -n openshift-mtv
oc get forkliftcontroller -n openshift-mtv
oc get routes -n openshift-mtv
```

### Step 3. Build the VMware credentials secret
Create a Secret for the vSphere provider credentials and certificate material.

### Step 4. Create the VMware source `Provider`
Define the vSphere source endpoint, secret reference, and optional VDDK image.

### Step 5. Configure VMware transfer endpoints with `Host`
For VMware migrations, add Host CRs for ESXi hosts that must use a specific migration network.

### Step 6. Create the OpenShift Virtualization destination `Provider`
Usually this is the local `host` provider or a remote OpenShift Virtualization destination.

### Step 7. Create target namespaces
Create a namespace per wave or per application domain.

Example:

```bash
for i in $(seq -w 1 10); do
  oc new-project migration-wave-${i}
done
```

### Step 8. Create reusable `NetworkMap` CRs
Map each vSphere source network/port group to either:
- `pod`
- `multus`
- `ignored`

Use `multus` for non-pod networks or VLAN-backed app segments.

### Step 9. Create reusable `StorageMap` CRs
Map each datastore to a destination `StorageClass` and access mode.

### Step 10. Decide warm vs cold migration per VM set
Use **warm** when:
- CBT is enabled
- downtime must be minimized
- the workload profile supports warm migration

Use **cold** when:
- CBT is not enabled
- the workload is simpler to cut over offline
- shared disks or guest-side dependencies make warm migration less attractive

### Step 11. Build one `Plan` per wave
Each plan references:
- source provider
- destination provider
- one network map
- one storage map
- target namespace
- the VM list
- optional hooks

### Step 12. Run one `Migration` per wave
Start the migration with a `Migration` CR that references the plan.

### Step 13. Validate runtime resources while the migration runs
Check the following objects:

```bash
oc get plans,migrations -n openshift-mtv
oc get datavolumes,pvc -A
oc get pods -A | egrep 'conversion|importer|pvcinit|virt-launcher'
oc get vm,vmi -A
```

### Step 14. Troubleshoot failures
Collect:
- MTV logs
- `conversion` pod logs
- `importer` pod logs when present
- `oc adm inspect ns/<namespace>`
- MTV must-gather

Examples:

```bash
oc adm inspect ns/openshift-mtv --dest-dir=inspect-mtv
oc adm must-gather --image=registry.redhat.io/migration-toolkit-virtualization/mtv-must-gather-rhel8:2.5.7
```

### Step 15. Cut over and validate applications
Validate:
- VM boot
- network reachability
- static IP preservation (if required)
- storage attachment
- app service health
- backup/monitoring enrollment
- DNS and load balancer cutover

### Step 16. Archive completed plans only after validation
Archive only after:
- application validation
- acceptance sign-off
- evidence collection
- rollback window expiration

---

## 6) Operational recommendations for a 1000-VM migration

### Architecture and batching
- Split by application/domain and by cutover window, not just by count.
- Keep disk-heavy VMs out of the same wave as latency-sensitive business apps.
- Use a pilot wave before the first production weekend.
- Keep warm and cold migrations separated in planning and reporting.

### Networking
- Use fast, dedicated transfer networks whenever possible.
- Keep NADs and target namespaces aligned before starting the first production wave.
- Pre-validate routing for transfer networks and app networks separately.

### Storage
- Validate target IOPS and latency with a pilot.
- Do not assume all datastores should map to the same target storage class.
- If you can use storage copy offload and your storage platform supports it, evaluate it for large-scale VMware migrations.

### Operations
- Standardize naming:
  - providers
  - maps
  - plans
  - migrations
  - target namespaces
- Use one evidence folder per wave for logs, CR YAMLs, screenshots, and sign-off.
- Automate log collection for every failed migration.
- Treat VM inventory quality as a prerequisite, not as a migration-time discovery task.

### Governance
- Add owner, application, business criticality, and cutover window columns to the planning CSV.
- Require wave readiness criteria:
  - provider connected
  - maps ready
  - namespace ready
  - storage validated
  - network validated
  - rollback owner assigned
  - business tester assigned

---

## 7) Suggested wave readiness checklist

- [ ] Source provider connected
- [ ] Destination provider connected
- [ ] ESXi host transfer network configured
- [ ] Network map validated
- [ ] Storage map validated
- [ ] Target namespace created
- [ ] Transfer network reachable
- [ ] Storage class validated
- [ ] VDDK configured (recommended for VMware)
- [ ] CBT enabled for warm candidates
- [ ] Pilot migration passed
- [ ] Rollback owner assigned
- [ ] Application tester assigned
- [ ] Backup/monitoring onboarding ready
- [ ] Support evidence collection script ready

---

## 8) Artifact set included with this package

1. `mtv_vmware_1000_vm_wave_plan.csv`
   - Example inventory and wave-planning file for 1000 VMs.
2. `mtv_vmware_migration_runbook_and_crd_inventory.md`
   - This document.
3. `mtv_vmware_sample_authored_and_generated_yamls.md`
   - Example YAMLs for authored MTV CRs and generated runtime objects.

---

## 9) References

- Red Hat Documentation: *Planning your migration to Red Hat OpenShift Virtualization 2.11*
- Red Hat Documentation: *Migrating your virtual machines to Red Hat OpenShift Virtualization 2.11*
- Red Hat Documentation: *Installing and using the Migration Toolkit for Virtualization 2.6*
- Red Hat Customer Portal: *Performance recommendations for migrating from VMware vSphere to OpenShift Virtualization*
