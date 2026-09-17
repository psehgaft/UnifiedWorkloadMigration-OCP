# KubeVirt Without Fear — VM + Container Demo

This demo accompanies the DevConf.US session **“KubeVirt Without Fear: Running VMs and Containers Together on One Platform.”** It is written for Red Hat OpenShift Virtualization and uses upstream KubeVirt APIs wherever possible.

## What the demo proves

> One OpenShift control plane can declaratively deploy, connect, operate, observe, and recover a hybrid application composed of a persistent VM and a containerized service, without erasing the operational differences between the two runtimes.

| Capability | Evidence produced by the demo |
|---|---|
| One API and desired-state model | `oc get vm,vmi,dv,pvc,deploy,pod,svc,route` returns both workload types and their dependencies. |
| Common service discovery | The frontend reaches the VM through `legacy-api.$NAMESPACE.svc`. |
| Persistent VM storage | A CDI `DataVolume` backs the boot disk and the request counter survives VMI recreation. |
| Workload-aware lifecycle | Kubernetes manages the Deployment; KubeVirt manages VM/VMI start, stop, restart, and reconciliation. |
| Common policy surface | Kubernetes labels, Services, NetworkPolicy, RBAC, events, and metrics apply across the application. |
| Recovery | Deleting the VMI causes the `VirtualMachine` controller to create a replacement instance. |
| Mobility, when eligible | Optional live migration moves the running VMI to another node if the VMI reports `LiveMigratable=True`. |

## Architecture

```text
Internet
   |
   v
OpenShift Route
   |
   v
modern-frontend Service -> modern-frontend Deployment (2 pods)
                                     |
                                     | HTTP + cluster DNS
                                     v
                              legacy-api Service
                                     |
                                     v
                              VirtualMachine / VMI
                                     |
                                     v
                            CDI DataVolume -> PVC
```

The Route exposes the container frontend only. The VM API remains a `ClusterIP` service and is reachable only from the frontend according to NetworkPolicy.

## Prerequisites

- An OpenShift cluster with OpenShift Virtualization installed and healthy.
- At least one schedulable virtualization-capable worker node.
- A default `StorageClass` that supports dynamic provisioning.
- Outbound access to `quay.io/containerdisks/fedora:latest` and `registry.access.redhat.com/ubi9/python-312:latest`, or mirrored equivalents.
- `oc`, plus `virtctl` for the optional live-migration step.
- Permissions to create a project, VM, DataVolume, PVC, Deployment, Service, Route, and NetworkPolicy.

Run the preflight check:

```bash
./scripts/preflight.sh
```

## Deploy

```bash
./scripts/deploy.sh
```

The default namespace is `kubevirt-without-fear`. Override it consistently:

```bash
NAMESPACE=my-hybrid-demo ./scripts/deploy.sh
```

The script applies the KubeVirt-compatible base and then the OpenShift Route. It waits for the DataVolume import, VM readiness, and frontend rollout.

## Run the guided demo

```bash
./scripts/demo.sh
```

Press Enter between stages. For an unattended rehearsal:

```bash
DEMO_AUTO=1 ./scripts/demo.sh
```

The guided flow:

1. Shows the unified inventory.
2. Calls the public Route and displays the frontend pod and VM backend identity.
3. Shows the VM’s persistent request counter.
4. Deletes the VMI to demonstrate controller reconciliation.
5. Calls the application again and confirms that the VM disk state survived.
6. Attempts live migration only when `virtctl` exists and the VMI is eligible.

## Upstream KubeVirt mode

The resources under `manifests/base` use Kubernetes and KubeVirt APIs. On a non-OpenShift KubeVirt cluster, omit the Route and use port forwarding:

```bash
kubectl apply -k manifests/base
kubectl -n kubevirt-without-fear port-forward service/modern-frontend 8080:8080
curl http://127.0.0.1:8080/
```

You may need to replace the OpenShift-friendly UBI image, adapt security policy, and provide a compatible default storage class.

## Operational interpretation

The demo does **not** claim that VMs and containers are operationally identical. A common control plane reduces tool and policy fragmentation, but VM disks, guest operating systems, backup consistency, migration eligibility, capacity reservations, and failure domains still require explicit design.

Use OpenShift Virtualization when platform consolidation and gradual modernization create more value than preserving a separate virtualization silo. Do not use it merely to avoid understanding Kubernetes or to force every VM into a platform whose storage, network, latency, device, or support requirements do not fit.

## Cleanup

```bash
./scripts/cleanup.sh
```

This deletes the demo namespace and all resources in it.

## Troubleshooting

```bash
oc -n kubevirt-without-fear get vm,vmi,dv,pvc,pod,svc,route
oc -n kubevirt-without-fear get events --sort-by=.lastTimestamp
oc -n kubevirt-without-fear describe vm legacy-api
oc -n kubevirt-without-fear logs deploy/modern-frontend
oc -n kubevirt-without-fear logs -l kubevirt.io=virt-launcher -c compute --tail=100
```

If the DataVolume import cannot pull the Fedora image, mirror the image into an approved registry and update `spec.dataVolumeTemplates[0].spec.source.registry.url` in `manifests/base/10-legacy-vm.yaml`.

## References

- [OpenShift Virtualization overview](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/virtualization/about)
- [KubeVirt architecture](https://kubevirt.io/user-guide/architecture/)
- [KubeVirt Service objects](https://kubevirt.io/user-guide/network/service_objects/)
- [KubeVirt disks and volumes](https://kubevirt.io/user-guide/storage/disks_and_volumes/)
- [KubeVirt live migration](https://kubevirt.io/user-guide/compute/live_migration/)
