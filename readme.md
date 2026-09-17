# Unified Workload Migration on OpenShift

This repository is an end-to-end guide for moving virtual machines to Red Hat OpenShift Virtualization, operating them with KubeVirt APIs, and modernizing selected application components as containers on the same OpenShift platform.

## Global objective

Demonstrate that an organization can assess and migrate existing virtual machines to OpenShift Virtualization, validate them with explicit acceptance and rollback criteria, and then operate VMs and containers through one Kubernetes control plane without hiding the runtime-specific constraints that matter.

## The complete journey

```mermaid
flowchart LR
    A[Discover and assess] --> B[Design target mappings]
    B --> C[Migrate with MTV]
    C --> D[Validate and cut over]
    D --> E[Operate on OpenShift Virtualization]
    E --> F[Modernize selectively]
```

The repository deliberately keeps migration and Day-2 operations together:

1. **Assess** the source estate, dependencies, guest operating systems, disks, networks, performance, and business criticality.
2. **Prepare** OpenShift Virtualization, Migration Toolkit for Virtualization (MTV), providers, credentials, transfer networks, target namespaces, and storage/network mappings.
3. **Migrate** in controlled pilot and production waves using cold or warm migration according to workload requirements and platform support.
4. **Validate and cut over** with technical and application checks, evidence capture, a named rollback owner, and an explicit rollback window.
5. **Operate** migrated VMs through KubeVirt/OpenShift Virtualization APIs alongside container workloads.
6. **Modernize selectively** by containerizing suitable application tiers while retaining VM components that still require a guest operating system.

## Migration guide

Start with the [unified migration guide](docs/unified-migration-guide.md). It connects the full migration process to the KubeVirt and OpenShift Virtualization operating model.

Detailed assets remain available:

- [`docs/mtv-migration-runbook.md`](docs/mtv-migration-runbook.md): MTV CRD inventory, detailed execution model, wave planning, validation, and troubleshooting.
- [`templates/mtv-crd.md`](templates/mtv-crd.md): example `Provider`, `NetworkMap`, `StorageMap`, `Plan`, `Migration`, and related resources.
- [`migration.ipynb`](migration.ipynb): complementary application modernization notebook for deploying local Java, PHP, or Ruby source with OpenShift S2I.

## DevConf.US demo

### KubeVirt Without Fear: Running VMs and Containers Together on One Platform

The demo under [`demos/kubevirt-without-fear`](demos/kubevirt-without-fear/) represents the **post-migration operating state**. It deploys:

- a Fedora-based `VirtualMachine` named `legacy-api`, managed by KubeVirt/OpenShift Virtualization;
- a persistent CDI `DataVolume` used as the VM boot disk;
- a Kubernetes `Service` that makes the VM discoverable by DNS;
- a containerized `modern-frontend` deployment that calls the VM API;
- an OpenShift `Route` that exposes only the frontend;
- network policies that restrict east-west access;
- a guided Day-2 flow for lifecycle, recovery, observation, and conditional live migration.

```mermaid
flowchart LR
    U[User] --> R[OpenShift Route]
    R --> F[Container frontend]
    F --> S[ClusterIP Service]
    S --> V[KubeVirt VM]
    V --> D[Persistent DataVolume]
```

Run the demo:

```bash
git clone https://github.com/psehgaft/UnifiedWorkloadMigration-OCP.git
cd UnifiedWorkloadMigration-OCP/demos/kubevirt-without-fear
./scripts/preflight.sh
./scripts/deploy.sh
./scripts/demo.sh
```

See the [demo guide](demos/kubevirt-without-fear/README.md) and the [presenter runbook](demos/kubevirt-without-fear/docs/presenter-runbook.md).

## How the migration and demo fit together

| Migration evidence | Post-migration evidence in the demo |
|---|---|
| Source inventory and compatibility assessment | Declarative VM and container inventory |
| Storage and network mappings | CDI DataVolume, PVC, Service, Route, and NetworkPolicy |
| Pilot/wave execution | Repeatable manifest and script-driven deployment |
| VM boot and application validation | VM readiness and container-to-VM connectivity |
| Cutover and recovery plan | Desired-state VMI recovery and persistent data verification |
| Mobility constraints | Conditional live migration based on reported eligibility |

The demo does not simulate VMware transport. MTV performs that migration. The demo proves what the migrated workload looks like and how it is operated after it reaches OpenShift Virtualization.

## Primary references

- [Migration Toolkit for Virtualization 2.11](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.11)
- [OpenShift Virtualization documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/virtualization/about)
- [KubeVirt architecture](https://kubevirt.io/user-guide/architecture/)
- [KubeVirt service objects](https://kubevirt.io/user-guide/network/service_objects/)
- [KubeVirt disks and volumes](https://kubevirt.io/user-guide/storage/disks_and_volumes/)
- [KubeVirt live migration](https://kubevirt.io/user-guide/compute/live_migration/)

## License and support

These assets are educational examples. Validate the installed MTV and OpenShift Virtualization versions, supported source providers, guest operating systems, image sources, resource sizes, storage classes, network design, security requirements, backup strategy, performance targets, and product support boundaries before production use.
