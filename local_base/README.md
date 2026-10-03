## A simple base lab configuration using minimal hardware

This is a small configuration using a Raspberry Pi 5 as a kubernetes control plane, and a Linux server for workers.

## Hardware
- Raspberry Pi 5
  - 8GB RAM
  - 256GB SSD hat
- lab1 and lab2
  - Intel
  - Ubuntu 24.04.1 LTS Server
  - 16GB and 32GB RAM

## Software
- Raspberry Pi OS (64-bit) on the Pi
- Ubuntu 24.04.1 LTS Server on lab1 and lab2
- Terraform v1.15.9

## Setup
Install and configure the appropriate OS for each system.


## Install

```bash
cd local_base/stacks/01-control-plane
terraform init
terraform apply -var-file=../../inventory/terraform.tfvars
```

The admin kubeconfig and a 24-hour worker join command are written under `stacks/01-control-plane/.generated/`. `terraform destroy` forgets the Terraform resource and leaves the cluster installed.

`02-workers` joins lab1 and lab2. Add their addresses and memory to `inventory/terraform.tfvars`, then:

```bash
cd local_base/stacks/02-workers
terraform init
terraform apply -var-file=../../inventory/terraform.tfvars
```

Each worker is named from that inventory entry. Flannel is already installed on the cluster, so the new nodes become Ready without a separate network install. `terraform destroy` forgets the worker resources and leaves the nodes joined.

## Manage

From `local_base/stacks/01-control-plane`, install the admin kubeconfig for `kubectl`. This replaces `~/.kube/config`.

```bash
mkdir -p ~/.kube
install -m 600 .generated/admin.conf ~/.kube/config
kubectl get nodes
```

The context is `kubernetes-admin@local-base`, and the API server is the Pi on port 6443. `admin.conf` is a cluster-admin credential, so leave it under `.generated/` and out of git.
