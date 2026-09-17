# Unified Migration Guide: From Existing VMs to KubeVirt and OpenShift Virtualization

This guide connects migration execution with the operating model demonstrated by **KubeVirt Without Fear**. It complements the detailed [MTV migration runbook](mtv-migration-runbook.md); it does not replace it.

## 1. Target outcome

The migration is complete only when the workload has crossed four gates:

1. **Platform gate:** the target OpenShift Virtualization platform has the required compute, storage, network, security, observability, backup, and support capabilities.
2. **Migration gate:** the VM is transferred by Migration Toolkit for Virtualization (MTV) using an approved cold or warm migration plan.
3. **Application gate:** the guest boots, the application passes functional and non-functional checks, and dependencies work from the target platform.
4. **Operations gate:** ownership, monitoring, backup, patching, recovery, capacity, and escalation are ready for steady-state service.

The goal is not merely to copy disks. The goal is to establish a supportable workload on OpenShift Virtualization and create a safe path for later modernization.

## 2. Understand the platform layers

| Layer | Upstream technology | Red Hat product capability | Migration role |
|---|---|---|---|
| VM API and runtime | KubeVirt | OpenShift Virtualization | Runs and manages `VirtualMachine` and `VirtualMachineInstance` resources. |
| Disk import and population | Containerized Data Importer (CDI) | Included with OpenShift Virtualization | Populates PVC-backed VM disks through `DataVolume` workflows. |
| Source-to-target migration | Forklift | Migration Toolkit for Virtualization (MTV) | Discovers source VMs and coordinates providers, mappings, plans, migrations, conversion, and transfer. |
| Platform services | Kubernetes | Red Hat OpenShift | Provides scheduling, RBAC, namespaces, Services, Routes, policy, observability, and GitOps integration. |

KubeVirt is the virtualization foundation. OpenShift Virtualization packages and integrates that foundation for an enterprise OpenShift environment. MTV orchestrates migration into that target.

## 3. Migration architecture

```mermaid
flowchart LR
    S[Source virtualization platform] --> P[MTV source Provider]
    P --> M[NetworkMap and StorageMap]
    M --> L[Migration Plan]
    L --> X[Cold or warm Migration]
    X --> V[OpenShift Virtualization VM]
    V --> O[Day-2 operations and modernization]
```

For VMware migrations, validate the source provider, credentials, vCenter and ESXi reachability, VDDK strategy, transfer network, Changed Block Tracking requirements for warm migration, and target capacity before building production plans.

## 4. Phase 1 — discover and assess

Build an authoritative inventory containing at least:

- application and business owner;
- source VM, cluster, datastore, network, CPU, memory, disks, firmware, and guest OS;
- application dependencies, ports, DNS, load balancers, identity, certificates, and external services;
- average and peak utilization, latency sensitivity, IOPS, throughput, and growth;
- special hardware, shared disks, affinity rules, passthrough devices, and licensing constraints;
- recovery objectives, backup method, maintenance windows, and acceptable downtime;
- target disposition: migrate as VM, modernize before migration, retire, replace, or defer.

Classify each workload by migration complexity and business criticality. Do not use VM count as the only wave-planning variable.

## 5. Phase 2 — prepare the target

Before the first pilot:

- install and validate OpenShift Virtualization and MTV versions supported by the target OpenShift release;
- size compute nodes and reserve capacity for migration overlap, failure domains, and recovery;
- define target namespaces, quotas, limits, RBAC, labels, and ownership;
- select storage classes for performance, access mode, snapshots, backup, and mobility requirements;
- configure pod, primary VM, secondary Multus, and transfer networks as required;
- configure monitoring, logging, alerting, backup, image access, and trusted certificates;
- agree on naming, IP/DNS handling, change records, cutover steps, and rollback ownership.

The target must be operationally ready before the migration tool begins moving workloads.

## 6. Phase 3 — configure MTV

| Resource | Purpose |
|---|---|
| `Provider` | Defines source and destination inventory endpoints. |
| `Secret` | Stores provider credentials and certificates. |
| `NetworkMap` | Maps source networks to OpenShift pod or Multus networks. |
| `StorageMap` | Maps source datastores or storage domains to target storage classes. |
| `Plan` | Selects VMs, mappings, destination namespace, migration type, and optional hooks. |
| `Migration` | Starts or controls execution of a plan. |
| `Hook` | Runs supported pre- or post-migration automation when required. |

Keep mappings reusable, but keep plans small enough to isolate failure domains and fit the approved cutover window.

## 7. Phase 4 — choose the migration method

### Cold migration

Choose cold migration when downtime is acceptable, the workload is simple to stop, warm migration prerequisites are unavailable, or consistency requirements favor a single offline transfer.

### Warm migration

Choose warm migration when the source and target combination supports it, the workload has a large disk footprint, downtime must be reduced, and the operational team can manage precopy, final cutover, and rollback complexity. For VMware, validate Changed Block Tracking and the current MTV support requirements.

Warm migration reduces the final outage; it does not remove the need for an application-consistent cutover.

## 8. Phase 5 — pilot and wave execution

Use a progressive wave model:

1. **Technical pilot:** low-risk representatives of each important guest, network, and storage pattern.
2. **Application pilot:** a complete application dependency group with business validation.
3. **Production waves:** grouped by dependency, cutover window, criticality, data size, and support team.
4. **Exception waves:** special devices, unsupported guests, shared-disk clusters, unusual network dependencies, or vendor-controlled systems.

For every wave, capture provider health, mappings, plan YAML, migration status, transfer/conversion logs, target VM resources, validation results, cutover approval, and rollback expiration.

## 9. Phase 6 — validate and cut over

Minimum validation should include:

- target `VirtualMachine`, `VirtualMachineInstance`, `DataVolume`, and PVC readiness;
- guest boot, drivers, clock, hostname, disks, filesystems, CPU/memory, and guest-agent health;
- IP, DNS, routing, firewall, service, certificate, and load-balancer behavior;
- application transactions, integrations, batch jobs, scheduled tasks, and data consistency;
- performance compared with the accepted baseline;
- monitoring, logging, backup, restore, patching, vulnerability management, and support access.

Rollback must have a trigger, decision owner, latest decision time, source recovery steps, DNS/load-balancer reversal, and data reconciliation procedure.

## 10. Phase 7 — operate on KubeVirt/OpenShift Virtualization

After acceptance, manage the VM through Kubernetes-native resources and OpenShift controls:

```bash
oc get vm,vmi,dv,pvc -A
oc describe vm <vm-name> -n <namespace>
oc get events -n <namespace> --sort-by=.lastTimestamp
virtctl console <vm-name> -n <namespace>
```

Adopt common controls for VMs and containers where they genuinely align: GitOps, RBAC, labels, namespaces, policy, Services, DNS, metrics, events, capacity governance, and change automation. Retain VM-specific processes for the guest OS, application-consistent backup, firmware, devices, and migration eligibility.

## 11. Phase 8 — modernize selectively

Migration and modernization do not have to happen in the same maintenance window. Once the VM is stable on OpenShift Virtualization, evaluate each application tier:

- **Retain as VM:** OS-coupled, vendor-controlled, device-dependent, or not economically justified to refactor.
- **Rehost then improve:** migrate first, then adopt GitOps, automation, observability, policy, backup, and standardized images.
- **Split the application:** keep a stateful or packaged backend as a VM and deploy new frontends or APIs as containers.
- **Replatform or containerize:** move suitable services to container images, Deployments, Operators, or serverless patterns.

The included demo shows the split-application model: a container frontend reaches a persistent VM backend through a Kubernetes Service while OpenShift provides a shared control plane.

## 12. Readiness checklist

- [ ] Inventory and dependency data are complete.
- [ ] Workload disposition is approved.
- [ ] Source and target providers are connected.
- [ ] Target capacity and failure domains are validated.
- [ ] Network and storage mappings are tested.
- [ ] Migration method and cutover window are approved.
- [ ] Pilot migrations passed.
- [ ] Application validation owner is assigned.
- [ ] Rollback trigger, owner, and deadline are documented.
- [ ] Monitoring, backup, restore, patching, and support are ready.
- [ ] Evidence retention and acceptance sign-off are defined.

## 13. Repository exercises

1. Follow [`mtv-migration-runbook.md`](mtv-migration-runbook.md) to design providers, mappings, plans, and migration waves.
2. Review [`../templates/mtv-crd.md`](../templates/mtv-crd.md) for declarative MTV examples.
3. Run [`../demos/kubevirt-without-fear`](../demos/kubevirt-without-fear/) to validate the target operating model: VM lifecycle, persistent storage, Services, NetworkPolicy, container-to-VM connectivity, recovery, and conditional live migration.
4. Use [`../migration.ipynb`](../migration.ipynb) as a complementary S2I exercise when evaluating application components for containerization.

## References

- [Migration Toolkit for Virtualization 2.11](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11)
- [OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/virtualization/about)
- [KubeVirt architecture](https://kubevirt.io/user-guide/architecture/)
- [KubeVirt networking and Services](https://kubevirt.io/user-guide/network/service_objects/)
- [KubeVirt storage](https://kubevirt.io/user-guide/storage/disks_and_volumes/)
- [KubeVirt live migration](https://kubevirt.io/user-guide/compute/live_migration/)
