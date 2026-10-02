terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "control_plane_ip" {
  description = "Reachable IP of the Raspberry Pi. kubeadm advertises this address."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.control_plane_ip}/32"))
    error_message = "control_plane_ip must be an IP address."
  }
}

variable "control_plane_subnet" {
  description = "On-link subnet that contains control_plane_ip. This stack does not change the Pi's address."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.control_plane_subnet))
    error_message = "control_plane_subnet must be a CIDR prefix."
  }
}

variable "control_plane_gateway" {
  description = "LAN gateway for the control plane. This stack does not change the Pi's routes."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.control_plane_gateway}/32"))
    error_message = "control_plane_gateway must be an IP address."
  }
}

variable "ssh_user" {
  description = "SSH user on the Pi. Needs passwordless sudo."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Private key used to SSH to the Pi."
  type        = string
}

variable "pod_cidr" {
  description = "Pod network CIDR. Passed to kubeadm and Flannel."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr must be a CIDR prefix."
  }
}

variable "service_cidr" {
  description = "Service network CIDR passed to kubeadm."
  type        = string
  default     = "10.96.0.0/12"

  validation {
    condition     = can(cidrnetmask(var.service_cidr))
    error_message = "service_cidr must be a CIDR prefix."
  }
}

variable "cluster_name" {
  description = "kubeadm cluster name."
  type        = string
  default     = "local-base"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a lowercase DNS label."
  }
}

variable "extra_api_sans" {
  description = "Extra Subject Alternative Names for the API server certificate. The control plane IP is always included."
  type        = list(string)
  default     = []
}

variable "kubeconfig_path" {
  description = "Where to write the admin kubeconfig on the machine running Terraform. Defaults to .generated/admin.conf in this stack."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes patch version to install from pkgs.k8s.io. An existing different version is left unchanged."
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

locals {
  api_sans       = distinct(concat([var.control_plane_ip], var.extra_api_sans))
  lan_prefix     = split("/", var.control_plane_subnet)[1]
  pod_prefix     = split("/", var.pod_cidr)[1]
  service_prefix = split("/", var.service_cidr)[1]
  kubeconfig_path = (
    var.kubeconfig_path != null && var.kubeconfig_path != ""
    ? var.kubeconfig_path
    : "${path.module}/.generated/admin.conf"
  )
  join_command_path = "${dirname(local.kubeconfig_path)}/join-command"
  kubeadm_config = templatefile("${path.module}/templates/kubeadm-config.yaml.tpl", {
    control_plane_ip   = var.control_plane_ip
    pod_cidr           = var.pod_cidr
    service_cidr       = var.service_cidr
    cluster_name       = var.cluster_name
    kubernetes_version = var.kubernetes_version
    api_sans           = local.api_sans
  })
}

resource "local_file" "kubeadm_config" {
  content              = local.kubeadm_config
  filename             = "${path.module}/.generated/kubeadm-config.yaml"
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "control_plane" {
  triggers = {
    kubeadm_config = local.kubeadm_config
    prepare        = file("${path.module}/scripts/prepare-node.sh")
    install        = file("${path.module}/scripts/install-control-plane.sh")
    wait           = file("${path.module}/scripts/wait-for-reboot.sh")
    fetch          = file("${path.module}/scripts/fetch-kubeconfig.sh")
    kubernetes     = var.kubernetes_version
    apt_key        = var.kubernetes_apt_key_fingerprint
    flannel        = file("${path.module}/files/kube-flannel.yml")
    pod_cidr       = var.pod_cidr
  }

  connection {
    type        = "ssh"
    host        = var.control_plane_ip
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  lifecycle {
    precondition {
      condition     = cidrhost("${var.control_plane_ip}/${local.lan_prefix}", 0) == cidrhost(var.control_plane_subnet, 0)
      error_message = "control_plane_ip is not inside control_plane_subnet."
    }
    precondition {
      condition = (
        cidrhost("${cidrhost(var.pod_cidr, 0)}/${local.service_prefix}", 0) != cidrhost(var.service_cidr, 0)
        && cidrhost("${cidrhost(var.service_cidr, 0)}/${local.pod_prefix}", 0) != cidrhost(var.pod_cidr, 0)
        && cidrhost("${var.control_plane_ip}/${local.pod_prefix}", 0) != cidrhost(var.pod_cidr, 0)
        && cidrhost("${var.control_plane_ip}/${local.service_prefix}", 0) != cidrhost(var.service_cidr, 0)
      )
      error_message = "pod_cidr and service_cidr must not overlap each other or the control plane address."
    }
  }

  # Replacing this resource re-runs the install. It does not reset a cluster that already has admin.conf.
  provisioner "file" {
    source      = "${path.module}/scripts/prepare-node.sh"
    destination = "/tmp/prepare-node.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-control-plane.sh"
    destination = "/tmp/install-control-plane.sh"
  }

  provisioner "file" {
    content     = local.kubeadm_config
    destination = "/tmp/kubeadm-config.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/files/kube-flannel.yml"
    destination = "/tmp/kube-flannel.yml"
  }

  provisioner "remote-exec" {
    inline = ["sudo -n bash /tmp/prepare-node.sh"]
  }

  provisioner "remote-exec" {
    inline = [
      "if [ -f /var/lib/home-lab/reboot-required ]; then sudo -n systemd-run --on-active=3s /usr/bin/systemctl reboot; fi",
    ]
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/wait-for-reboot.sh"
    environment = {
      SSH_KEY    = var.ssh_private_key_path
      SSH_TARGET = "${var.ssh_user}@${var.control_plane_ip}"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo -n env KUBERNETES_VERSION='${var.kubernetes_version}' POD_CIDR='${var.pod_cidr}' KUBERNETES_APT_KEY_FINGERPRINT='${var.kubernetes_apt_key_fingerprint}' bash /var/lib/home-lab/install-control-plane.sh",
    ]
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/fetch-kubeconfig.sh"
    environment = {
      SSH_KEY           = var.ssh_private_key_path
      SSH_TARGET        = "${var.ssh_user}@${var.control_plane_ip}"
      KUBECONFIG_PATH   = local.kubeconfig_path
      JOIN_COMMAND_PATH = local.join_command_path
    }
  }
}

output "api_endpoint" {
  description = "Stable API endpoint workers use to join."
  value       = "${var.control_plane_ip}:6443"
}

output "kubeconfig_path" {
  description = "Admin kubeconfig written on the machine that ran Terraform."
  value       = local.kubeconfig_path
}

output "join_command_path" {
  description = "kubeadm join command for the worker stack. The token expires after 24 hours."
  value       = local.join_command_path
}
