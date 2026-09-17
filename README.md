# Unified Workload Migration on OpenShift

This repository contains practical assets for moving and operating virtual-machine workloads on Red Hat OpenShift Virtualization while modern container workloads run on the same platform.

## Featured DevConf.US demo

### KubeVirt Without Fear: Running VMs and Containers Together on One Platform

**Global objective:** Prove that one OpenShift control plane can declaratively deploy, connect, operate, observe, and recover a hybrid application composed of a persistent virtual machine and a containerized service, while preserving the workload-specific requirements of each runtime.

The demo under [`demos/kubevirt-without-fear`](demos/kubevirt-without-fear/) deploys:

- a Fedora-based `VirtualMachine` named `legacy-api`, managed by KubeVirt/OpenShift Virtualization;
- a persistent CDI `DataVolume` used as the VM boot disk;
- a Kubernetes `Service` that makes the VM discoverable by DNS;
- a containerized `modern-frontend` deployment that calls the VM API;
- an OpenShift `Route` that exposes only the frontend;
- network policies that restrict east-west access;
- a guided Day-2 flow for lifecycle, recovery, observation, and optional live migration.

```text
User -> OpenShift Route -> modern-frontend (Deployment)
                              |
                              v
                       legacy-api (Service)
                              |
                              v
                    legacy-api (VirtualMachine)
                              |
                              v
                       persistent DataVolume
```

Start here:

```bash
git clone https://github.com/psehgaft/UnifiedWorkloadMigration-OCP.git
cd UnifiedWorkloadMigration-OCP/demos/kubevirt-without-fear
./scripts/preflight.sh
./scripts/deploy.sh
./scripts/demo.sh
```

See the [demo guide](demos/kubevirt-without-fear/README.md) and the [presenter runbook](demos/kubevirt-without-fear/docs/presenter-runbook.md).

## VMware migration assets

The repository also retains the existing Migration Toolkit for Virtualization material:

- [`migration.ipynb`](migration.ipynb): migration planning notebook;
- [`templates/mtv-crd.md`](templates/mtv-crd.md): MTV custom-resource examples;
- [`docs/mtv-migration-runbook.md`](docs/mtv-migration-runbook.md): CRD inventory and 1,000-VM execution model.

## References

- [Red Hat OpenShift Virtualization documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/virtualization/about)
- [KubeVirt architecture](https://kubevirt.io/user-guide/architecture/)
- [KubeVirt service objects](https://kubevirt.io/user-guide/network/service_objects/)
- [KubeVirt disks and volumes](https://kubevirt.io/user-guide/storage/disks_and_volumes/)
- [KubeVirt live migration](https://kubevirt.io/user-guide/compute/live_migration/)

## License and support

The assets are educational examples. Review image sources, resource sizes, network policy, storage classes, security requirements, and support boundaries before using them in production.
