terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

variable "control_plane_ip" {
  description = "IP of the control plane. Used to request a fresh kubeadm join command."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.control_plane_ip}/32"))
    error_message = "control_plane_ip must be an IP address."
  }
}

variable "ssh_user" {
  description = "SSH user on the workers and the control plane. Needs passwordless sudo."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Private key used to SSH to the workers and the control plane."
  type        = string
}

variable "kubeconfig_path" {
  description = "Admin kubeconfig written by the control-plane stack."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes patch version. Must match the control plane."
  type        = string
  default     = "1.37.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a major.minor.patch version, such as 1.37.1."
  }
}

variable "kubernetes_apt_key_fingerprint" {
  description = "Fingerprint of the pkgs.k8s.io signing key. The install refuses any other key. This key expires 2026-12-29."
  type        = string
  default     = "DE15B14486CD377B9E876E1A234654DA9A296436"

  validation {
    condition     = can(regex("^[A-F0-9]{40}$", var.kubernetes_apt_key_fingerprint))
    error_message = "kubernetes_apt_key_fingerprint must be 40 uppercase hex characters."
  }
}

variable "workers" {
  description = "Intel workers to join. name becomes the Kubernetes node name."
  type = list(object({
    name      = string
    ip        = string
    memory_gb = number
  }))

  validation {
    condition = alltrue([
      for worker in var.workers : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", worker.name))
    ])
    error_message = "Each worker name must be a lowercase DNS label."
  }

  validation {
    condition = alltrue([
      for worker in var.workers : can(cidrnetmask("${worker.ip}/32")) && worker.memory_gb > 0
    ])
    error_message = "Each worker needs an IP address and a positive memory_gb."
  }
}

locals {
  kubeconfig_path = (
    var.kubeconfig_path != null && var.kubeconfig_path != ""
    ? var.kubeconfig_path
    : "${path.module}/../01-control-plane/.generated/admin.conf"
  )
  workers = { for worker in var.workers : worker.name => worker }
}

resource "null_resource" "worker" {
  for_each = local.workers

  triggers = {
    name       = each.value.name
    ip         = each.value.ip
    memory_gb  = tostring(each.value.memory_gb)
    install    = file("${path.module}/scripts/install-worker.sh")
    fetch_join = file("${path.module}/scripts/fetch-join-command.sh")
    label      = file("${path.module}/scripts/label-worker.sh")
    kubernetes = var.kubernetes_version
    apt_key    = var.kubernetes_apt_key_fingerprint
  }

  connection {
    type        = "ssh"
    host        = each.value.ip
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # A fresh token is requested at create time. It is not a trigger, so a later apply does not rejoin the node.
  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/fetch-join-command.sh"
    environment = {
      SSH_KEY           = var.ssh_private_key_path
      SSH_TARGET        = "${var.ssh_user}@${var.control_plane_ip}"
      JOIN_COMMAND_PATH = "${path.module}/.generated/join-${each.key}"
    }
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-worker.sh"
    destination = "/tmp/install-worker.sh"
  }

  provisioner "file" {
    source      = "${path.module}/.generated/join-${each.key}"
    destination = "/tmp/kubeadm-join"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo -n env KUBERNETES_VERSION='${var.kubernetes_version}' KUBERNETES_APT_KEY_FINGERPRINT='${var.kubernetes_apt_key_fingerprint}' NODE_NAME='${each.key}' bash /tmp/install-worker.sh",
    ]
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/label-worker.sh"
    environment = {
      KUBECONFIG_PATH = local.kubeconfig_path
      NODE_NAME       = each.key
      MEMORY_GB       = tostring(each.value.memory_gb)
    }
  }
}

output "worker_names" {
  description = "Kubernetes node names for the joined workers."
  value       = [for worker in var.workers : worker.name]
}
