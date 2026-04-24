# Sample YAMLs for a VMware -> OpenShift Virtualization migration with MTV

> Purpose: This file collects the main YAML objects you author directly, plus the principal objects you typically see generated during execution.
> Important: Some runtime status fields and generated object names vary by MTV, CDI, KubeVirt, and storage/network plugins. Treat generated examples below as representative examples, not byte-for-byte output.

---

## 1) VMware credentials Secret (authored)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vmware-prod-vcenter-secret
  namespace: openshift-mtv
type: Opaque
stringData:
  user: administrator@vsphere.local
  password: CHANGE_ME
  insecureSkipVerify: "false"
  cacert: |
    -----BEGIN CERTIFICATE-----
    REPLACE_WITH_CA_CERT
    -----END CERTIFICATE-----
```

---

## 2) VMware source Provider (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: vmware-prod-vcenter
  namespace: openshift-mtv
spec:
  type: vsphere
  url: https://vcenter.example.com/sdk
  settings:
    vddkInitImage: image-registry.openshift-image-registry.svc:5000/openshift/vddk:latest
    sdkEndpoint: vcenter
  secret:
    name: vmware-prod-vcenter-secret
    namespace: openshift-mtv
```

---

## 3) VMware Host mapping for transfer network (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Host
metadata:
  name: esxi-host-01
  namespace: openshift-mtv
spec:
  provider:
    name: vmware-prod-vcenter
    namespace: openshift-mtv
  id: host-101
  ipAddress: 10.70.30.11
```

> Create one Host CR per ESXi host that needs an explicit migration-network association.

---

## 4) OpenShift Virtualization destination Provider (authored)

### Option A: local cluster `host` provider
If the target is the same cluster where MTV runs, the local provider is often used.

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: host
  namespace: openshift-mtv
spec:
  type: openshift
```

### Option B: remote OpenShift Virtualization provider
```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: ocpv-remote-dr
  namespace: openshift-mtv
spec:
  type: openshift
  url: https://api.ocpv-remote.example.com:6443
  secret:
    name: ocpv-remote-token
    namespace: openshift-mtv
```

---

## 5) NetworkAttachmentDefinition for a transfer/app network (authored, Multus)

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: migration-transfer-net
  namespace: migration-wave-01
  annotations:
    forklift.konveyor.io/route: 10.70.30.1
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "name": "migration-transfer-net",
      "type": "macvlan",
      "master": "bond0.730",
      "mode": "bridge",
      "ipam": {
        "type": "whereabouts",
        "range": "10.70.30.0/24"
      }
    }
```

---

## 6) NetworkMap (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: NetworkMap
metadata:
  name: vmware-netmap-wave-01
  namespace: openshift-mtv
spec:
  map:
    - destination:
        name: default
        type: pod
      source:
        id: network-201
        name: VM Network
    - destination:
        name: app-vlan-120
        namespace: migration-wave-01
        type: multus
      source:
        id: network-202
        name: VLAN120-App
    - destination:
        name: ignored
        type: ignored
      source:
        id: network-203
        name: Backup-Network
  provider:
    source:
      name: vmware-prod-vcenter
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
```

---

## 7) StorageMap (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: StorageMap
metadata:
  name: vmware-storagemap-wave-01
  namespace: openshift-mtv
spec:
  map:
    - destination:
        storageClass: ocs-rbd
        accessMode: ReadWriteOnce
      source:
        id: datastore-301
    - destination:
        storageClass: ocs-cephfs
        accessMode: ReadWriteMany
      source:
        id: datastore-302
  provider:
    source:
      name: vmware-prod-vcenter
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
```

---

## 8) Optional Hook (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Hook
metadata:
  name: linux-postcheck
  namespace: openshift-mtv
spec:
  image: quay.io/kubev2v/hook-runner
  serviceAccount: forklift-controller
  playbook: |
    LS0tCi0gbmFtZTogUG9zdG1pZ3JhdGlvbiBDaGVjawogIGhvc3RzOiBhbGwKICB0YXNrczoKICAtIG5hbWU6
    IFRlc3QgY2xvdWQtaW5pdAogICAgY29tbWFuZDogImNsb3VkLWluaXQgc3RhdHVzIC0tbG9uZyIK
```

---

## 9) Plan for one 100-VM wave (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: wave-01-vmware-to-ocpv
  namespace: openshift-mtv
spec:
  warm: true
  provider:
    source:
      name: vmware-prod-vcenter
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    network:
      name: vmware-netmap-wave-01
      namespace: openshift-mtv
    storage:
      name: vmware-storagemap-wave-01
      namespace: openshift-mtv
  targetNamespace: migration-wave-01
  vms:
    - id: vm-10001
      name: vmware-prod-0001
      hooks:
        - hook:
            name: linux-postcheck
            namespace: openshift-mtv
          step: PostHook
    - id: vm-10002
      name: vmware-prod-0002
    - id: vm-10003
      name: vmware-prod-0003
    - id: vm-10004
      name: vmware-prod-0004
    - id: vm-10005
      name: vmware-prod-0005
```

> In the real 1000-VM example, create 10 Plan CRs of 100 VMs each, or another structure that stays below product limits and operational risk limits.

---

## 10) Migration execution CR (authored)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: wave-01-vmware-to-ocpv-run-01
  namespace: openshift-mtv
spec:
  plan:
    name: wave-01-vmware-to-ocpv
    namespace: openshift-mtv
  cutover: "2026-05-08T22:00:00-04:00"
```

---

# Objects commonly generated during execution

## 11) DataVolume generated by MTV/CDI (generated example)

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: import-vmware-prod-0001-disk-0
  namespace: migration-wave-01
  labels:
    migration.konveyor.io/plan: wave-01-vmware-to-ocpv
spec:
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 80Gi
    storageClassName: ocs-rbd
  source:
    blank: {}
```

> During VMware cold migration to the local cluster, MTV uses DataVolumes and then creates conversion pods that run `virt-v2v`.

---

## 12) PVC created from the DataVolume (generated example, standard resource)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: import-vmware-prod-0001-disk-0
  namespace: migration-wave-01
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 80Gi
  storageClassName: ocs-rbd
```

---

## 13) Hook Job (generated example, standard resource)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: wave-01-vmware-to-ocpv-vm-10001-posthook
  namespace: openshift-mtv
spec:
  template:
    spec:
      serviceAccountName: forklift-controller
      restartPolicy: Never
      containers:
        - name: hook
          image: quay.io/kubev2v/hook-runner
```

---

## 14) VirtualMachine created after disk transfer/conversion (generated example)

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vmware-prod-0001
  namespace: migration-wave-01
  labels:
    migration.konveyor.io/plan: wave-01-vmware-to-ocpv
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/domain: vmware-prod-0001
    spec:
      domain:
        cpu:
          cores: 4
        resources:
          requests:
            memory: 8Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: import-vmware-prod-0001-disk-0
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              chpasswd:
                expire: false
```

---

## 15) VirtualMachineInstance when the migrated VM is started (generated example)

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachineInstance
metadata:
  name: vmware-prod-0001
  namespace: migration-wave-01
spec:
  domain:
    cpu:
      cores: 4
    resources:
      requests:
        memory: 8Gi
```

---

## 16) Conversion pod you typically see while VMware disks are converted (generated example, standard Pod)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: wave-01-vmware-to-ocpv-conversion-abcde
  namespace: openshift-mtv
  labels:
    app: forklift
    migration.konveyor.io/plan: wave-01-vmware-to-ocpv
spec:
  restartPolicy: Never
  containers:
    - name: conversion
      image: registry.redhat.io/migration-toolkit-virtualization/mtv-virt-v2v-rhel8:latest
```

---

## 17) Plan status excerpt after success (generated example)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: wave-01-vmware-to-ocpv
  namespace: openshift-mtv
status:
  conditions:
    - category: Advisory
      message: The plan is ready.
      status: "True"
      type: Ready
  migration:
    name: wave-01-vmware-to-ocpv-run-01
    namespace: openshift-mtv
```

---

## 18) Migration status excerpt during execution (generated example)

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: wave-01-vmware-to-ocpv-run-01
  namespace: openshift-mtv
status:
  phase: Running
  vms:
    completed: 38
    failed: 2
    running: 60
```

---

# Practical notes

1. The objects above are the **main authored and generated objects** in a standard VMware -> OpenShift Virtualization path.
2. Not every environment will show identical status blocks.
3. Pod names, Job names, PVC names, and some labels are generated dynamically.
4. If you are using a remote destination cluster or warm migration, the runtime object pattern changes slightly, but the authored objects remain centered on:
   - `Provider`
   - `Host`
   - `NetworkMap`
   - `StorageMap`
   - `Hook`
   - `Plan`
   - `Migration`

---

# Suggested validation commands

```bash
oc get providers,hosts,networkmaps,storagemaps,hooks,plans,migrations -n openshift-mtv
oc get datavolumes,pvc,vm,vmi -A
oc get pods -A | egrep 'conversion|importer|pvcinit|virt-launcher'
oc describe plan wave-01-vmware-to-ocpv -n openshift-mtv
oc describe migration wave-01-vmware-to-ocpv-run-01 -n openshift-mtv
```
