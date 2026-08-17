# Kubernetes 1.32 → 1.36 Upgrade Plan

## Overview

Upgrade the `luzme-2026` cluster from Kubernetes 1.32.2 to 1.36.2, one minor version at a time. Each step is a separate `terraform apply` — Terraform detects the version change and runs provisioning scripts remotely via SSH.

**Upgrade order:** Master(s) first, then workers/storage sequentially.

**Target versions (final state):**
- Kubernetes: 1.36.2
- cri-tools: 1.36
- Calico: 3.32.1
- Autoscaler: 1.36.0

---

## Pre-Flight Checks

Before starting, verify:

1. **Brightbox cloud-controller-manager `1.36.2` tag exists** in `cr.brightbox.com/acc-juq13/public/`:
   ```bash
   # Check if the image tag exists (run from a machine with docker + credentials)
   docker manifest inspect cr.brightbox.com/acc-juq13/public/khaxan/brightbox-cloud-controller-manager:1.36.2
   ```
   If this fails, contact Brightbox or wait for the tag to be published. Steps 1–3 can proceed without this.

2. **Current cluster health:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   kubectl get events --sort-by=.metadata.creationTimestamp | tail -20
   ```

3. **etcd backup** (recommended):
   ```bash
   ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
   ```

---

## Step 1: 1.32.2 → 1.33.x

### Files to edit
- `terraform.tfvars` (line 23–25)

### Changes

**`terraform.tfvars`:**
```hcl
kubernetes_release = "1.33.7"    # latest 1.33 patch — check pkgs.k8s.io for exact version
critools_release = "1.33"
```

### Apply
```bash
terraform plan    # review — should show master + worker upgrades
terraform apply
```

### Verify
```bash
kubectl get nodes -o wide    # all nodes should report v1.33.x
kubectl get pods -A          # all pods Running
```

### No template changes needed
The `v1beta4` case in `kubeadm-config`, `install-worker-userdata`, and `install-master-mirror` already covers `1.3[12345].*`.

---

## Step 2: 1.33.x → 1.34.x

### Files to edit
- `terraform.tfvars`

### Changes

**`terraform.tfvars`:**
```hcl
kubernetes_release = "1.34.x"    # latest 1.34 patch
critools_release = "1.34"
```

### Apply & Verify
Same as Step 1.

### No template changes needed.

---

## Step 3: 1.34.x → 1.35.x

### Files to edit
- `terraform.tfvars`

### Changes

**`terraform.tfvars`:**
```hcl
kubernetes_release = "1.35.x"    # latest 1.35 patch
critools_release = "1.35"
autoscaler_release = "1.35.0"
```

### Apply & Verify
Same as Step 1.

### Notes
- IPVS kube-proxy deprecation warnings will appear in logs — these are non-blocking.
- No template changes needed.

---

## Step 4: 1.35.x → 1.36.x (requires code changes)

This step has breaking changes: kubeadm v1beta3 was removed in 1.36. The version-switch case statements must be updated before applying.

### Files to edit

| File | Line(s) | Change |
|------|---------|--------|
| `terraform.tfvars` | 23–25 | Version bumps + calico |
| `variables.tf` | 186–208 | Update defaults for kubernetes_release, critools_release, autoscaler_release, calico_release |
| `master/templates/kubeadm-config` | 14–20 | Add `1.3[6-9].*` case |
| `worker/templates/install-worker-userdata` | 81–87 | Add `1.3[6-9].*` case |
| `master/templates/install-master-mirror` | 304–310 | Add `1.3[6-9].*` case |

### Task 4.1: Update case statements (3 files)

All three files have identical case statement structures. Add a new pattern after the existing `1.3[12345].*` case:

**`master/templates/kubeadm-config` (line 14–20):**

Replace:
```bash
        1.3[12345].*)
            v1beta4
            ;;
        *)
            echo "Version ${kubernetes_release} not supported"
            exit 3
    esac
```

With:
```bash
        1.3[12345].*)
            v1beta4
            ;;
        1.3[6-9].*)
            v1beta4
            ;;
        *)
            echo "Version ${kubernetes_release} not supported"
            exit 3
    esac
```

**`worker/templates/install-worker-userdata` (line 81–87):**

Replace:
```bash
    1.3[12345].*)
        v1beta4
        ;;
    *)
        echo "Version ${kubernetes_release} not supported"
        exit 3
esac
```

With:
```bash
    1.3[12345].*)
        v1beta4
        ;;
    1.3[6-9].*)
        v1beta4
        ;;
    *)
        echo "Version ${kubernetes_release} not supported"
        exit 3
esac
```

**`master/templates/install-master-mirror` (line 304–310):**

Replace:
```bash
    1.3[12345].*)
        v1beta4
        ;;
    *)
        echo "Version ${kubernetes_release} not supported"
        exit 3
esac
```

With:
```bash
    1.3[12345].*)
        v1beta4
        ;;
    1.3[6-9].*)
        v1beta4
        ;;
    *)
        echo "Version ${kubernetes_release} not supported"
        exit 3
esac
```

### Task 4.2: Update `variables.tf` defaults

**`variables.tf` (lines 186–208):**

Replace:
```hcl
variable "kubernetes_release" {
  type        = string
  description = "Version of Kubernetes to install"
  default     = "1.35.2"
}

variable "critools_release" {
  type        = string
  description = "Version of cri-tools to install"
  default     = "1.35"
}

variable "autoscaler_release" {
  type        = string
  description = "Version of Vertical Autoscaler to install if the scaling features are activated. This needs to be the same minor version as the k8s release"
  default     = "1.35.0"
}

variable "calico_release" {
  type        = string
  description = "Version of Calico plugin to install"
  default     = "3.31.4"
}
```

With:
```hcl
variable "kubernetes_release" {
  type        = string
  description = "Version of Kubernetes to install"
  default     = "1.36.2"
}

variable "critools_release" {
  type        = string
  description = "Version of cri-tools to install"
  default     = "1.36"
}

variable "autoscaler_release" {
  type        = string
  description = "Version of Vertical Autoscaler to install if the scaling features are activated. This needs to be the same minor version as the k8s release"
  default     = "1.36.0"
}

variable "calico_release" {
  type        = string
  description = "Version of Calico plugin to install"
  default     = "3.32.1"
}
```

### Task 4.3: Update `terraform.tfvars`

**`terraform.tfvars` (lines 23–25):**

Replace:
```hcl
kubernetes_release = "1.32.2" # "1.32.12"
# critools_release = "1.35.0"
critools_release = "1.32"
```

With:
```hcl
kubernetes_release = "1.36.2"
critools_release = "1.36"
```

### Task 4.4: Update Calico manifest (if needed)

The `install_network_controllers()` function in `master/templates/install-master` (line 159) fetches Calico from:
```
https://raw.githubusercontent.com/projectcalico/calico/v${calico_release}/manifests/calico-vxlan.yaml
```

This URL is already dynamic and will resolve to `v3.32.1` once `calico_release` is updated. **No change needed to this function.**

However, the version check at line 182–190 must also pass for 3.32:
```bash
case "${calico_release}" in
    3.2[3-9]*)
        ;;
    3.2*)
        echo "Calico release ${calico_release} is too old..."
        exit 1
        ;;
esac
```

The pattern `3.2[3-9]*` matches `3.23`–`3.29`. It does **not** match `3.32` (which is `3.3*`, not `3.2*`). However, looking more carefully: `3.32` starts with `3.3`, not `3.2`. The pattern `3.2*` won't match `3.32`, so the "too old" block won't trigger. But the success case `3.2[3-9]*` also won't match. The case falls through without error, so this is fine — Calico 3.32 will proceed past this check.

**No change needed to the Calico version check.**

### Task 4.5: Apply and verify

```bash
terraform plan    # review all changes
terraform apply
```

### Verify
```bash
kubectl get nodes -o wide    # all nodes v1.36.2
kubectl get pods -A          # all pods Running
kubectl get cm kubeadm-config -n kube-system -o yaml    # verify config API version is v1beta4
```

### Check for warnings
```bash
# IPVS deprecation warnings (expected, non-blocking)
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50

# Calico health
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=calico-node --tail=20
```

---

## Post-Upgrade Cleanup

After all nodes are on 1.36.2:

1. **Remove old held packages** (should happen automatically via `install-packages` script, but verify):
   ```bash
   # On each node
   dpkg -l | grep -E 'kubelet|kubectl|kubeadm|cri-tools' | grep -v 1.36
   ```

2. **Verify autoscaler** (if enabled):
   ```bash
   kubectl get deployment -n kube-system vertical-pod-autoscaler
   ```

3. **Commit the changes:**
   ```bash
   git add terraform.tfvars variables.tf master/templates/kubeadm-config worker/templates/install-worker-userdata master/templates/install-master-mirror
   git commit -m "chore: upgrade kubernetes 1.32 → 1.36"
   ```

---

## Rollback

If a step fails:

1. **Check Terraform state:** `terraform state list` to see what resources exist
2. **Check node status:** `kubectl get nodes` — nodes may be in NotReady state
3. **Manual recovery on a node:**
   ```bash
   # Revert held packages
   sudo apt-mark unhold kubelet kubectl kubeadm cri-tools containerd
   sudo apt-get install -y --allow-change-held-packages kubelet=1.32.x-* kubectl=1.32.x-* kubeadm=1.32.x-*
   sudo apt-mark hold kubelet kubectl kubeadm
   sudo systemctl restart kubelet
   ```
4. **Revert terraform.tfvars** to the previous version and re-apply.

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Brightbox cloud-controller-manager `1.36.x` tag missing | Pods fail to start | Verify tag exists before Step 4 |
| Calico 3.32 manifest incompatibility | Network failures | Calico 3.32 is officially tested on K8s 1.36 |
| kubeadm v1beta3 removal breaks templates | Init/join fails | Case statement updates (Task 4.1) |
| cgroup v1 deprecation (`FailCgroupV1=true` default) | Kubelet fails on cgroup v1 | Ubuntu Noble uses cgroup v2 — no issue |
| etcd upgrade failure | Cluster unavailable | Take etcd snapshot backup before each step |
