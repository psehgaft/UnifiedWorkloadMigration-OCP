# Presenter Runbook

## Demo goal

Prove that a single OpenShift control plane can deploy and operate a hybrid application consisting of a persistent VM backend and container frontend while preserving runtime-specific operational requirements.

## Recommended timing

| Segment | Time | Proof point |
|---|---:|---|
| Preflight and architecture recap | 1 minute | KubeVirt, CDI, storage, and Route APIs are ready. |
| Unified inventory | 1 minute | VM, VMI, DataVolume, Deployment, Pods, Services, and Route share the API surface. |
| Application request | 1 minute | Container-to-VM DNS and service connectivity work. |
| VM/VMI lifecycle | 2 minutes | Desired state is separate from the current runtime instance. |
| Recovery and persistence | 3 minutes | VMI recreation restores service and preserves disk state. |
| Optional live migration | 2–4 minutes | Mobility works when the platform reports the VMI eligible. |
| Conclusion | 1 minute | Common control plane, explicit workload constraints. |

## Before the session

1. Use a multi-node OpenShift cluster with OpenShift Virtualization healthy.
2. Run `./scripts/preflight.sh` and resolve every warning that affects your planned path.
3. Run `./scripts/deploy.sh` at least 30 minutes before the session so image pulls are cached.
4. Run `DEMO_AUTO=1 ./scripts/demo.sh` once, then redeploy to reset the request counter if desired.
5. Open the Route in a browser and keep a terminal at 140% zoom.
6. If live migration matters, verify `LiveMigratable=True` and test the target storage and network path.
7. Keep screenshots of the inventory, application page, old/new VMI UIDs, and migration result as a fallback.

## Talk track

### Unified inventory

“The common control plane is visible here. The VM is not converted into a container. Instead, KubeVirt extends the Kubernetes API with VM-aware resources while Kubernetes still supplies scheduling, policy, storage, and networking primitives.”

### Application request

“The browser reaches a container through an OpenShift Route. That container resolves a regular Kubernetes Service whose endpoint is a VMI. No external load balancer or separate virtualization DNS workflow is required for this internal call.”

### VM and VMI

“The VirtualMachine is desired state; the VirtualMachineInstance is the running instance. This distinction is comparable to a controller and the workload instance it manages, but VM lifecycle semantics remain explicit.”

### Recovery

“I am deleting the runtime instance, not the VirtualMachine definition. The controller creates a replacement VMI. The application returns, and the counter continues because the disk is persistent.”

### Live migration

“We ask the platform whether this VMI is live-migratable before requesting migration. Shared storage, network bindings, devices, and topology still govern eligibility. A unified platform does not repeal physics.”

## Failure branches

| Symptom | Likely cause | Presenter action |
|---|---|---|
| DataVolume remains `ImportInProgress` | Registry, proxy, mirror, or storage issue | Show the cached screenshots; do not troubleshoot registry access live. |
| VM is running but not ready | cloud-init or guest service still starting | Show `oc describe vmi` and wait up to two minutes. |
| Frontend returns 503 | NetworkPolicy, VM readiness, or Service selector | Show endpoints with `oc get endpoints legacy-api`. |
| Live migration is rejected | VMI not eligible, often storage/access mode or device related | Treat the rejection as the trade-off lesson and explain the reported condition. |
| Route is unavailable | Non-OpenShift environment | Use `port-forward` and keep the rest of the demo unchanged. |

## Safe reset

```bash
./scripts/cleanup.sh
./scripts/deploy.sh
```

Cleanup removes the complete demo namespace, including the persistent VM disk.
