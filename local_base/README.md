## A simple base lab configuration using minimal hardware

This is a small configuration using a Raspberry Pi 5 as a kubernetes control plane, and a Linux server for workers.

## Hardware
- Raspberry Pi 5
  - 8GB RAM
  - 256GB SSD hat
- Dell OptiPlex 7060 Micro
  - 32GB RAM
  - 512GB SSD

## Software
- Raspberry Pi OS (64-bit) on the Pi
- Ubuntu 26.04.1 LTS on the Dell
- Terraform v1.15.9

## Setup


## Install

```bash
cd local_base/stacks/01-control-plane
terraform init
terraform apply -var-file=../../inventory/terraform.tfvars
```

The admin kubeconfig and a 24-hour worker join command are written under `stacks/01-control-plane/.generated/`. `terraform destroy` forgets the Terraform resource and leaves the cluster installed.

## Manage

From `local_base/stacks/01-control-plane`, install the admin kubeconfig for `kubectl`. This replaces `~/.kube/config`.

```bash
mkdir -p ~/.kube
install -m 600 .generated/admin.conf ~/.kube/config
kubectl get nodes
```

The context is `kubernetes-admin@local-base`, and the API server is the Pi on port 6443. `admin.conf` is a cluster-admin credential, so leave it under `.generated/` and out of git.
