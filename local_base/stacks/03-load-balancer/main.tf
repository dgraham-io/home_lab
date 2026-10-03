terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

variable "kubeconfig_path" {
  description = "Admin kubeconfig for the cluster that will announce load-balancer addresses."
  type        = string
}

variable "chart_version" {
  description = "MetalLB chart version."
  type        = string
  default     = "0.16.1"
}

variable "address_pool" {
  description = "Inclusive LAN range MetalLB may assign to LoadBalancer services. Must not overlap node addresses."
  type        = string
}

locals {
  namespace = "metallb-system"
}

resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = var.chart_version
  namespace        = local.namespace
  create_namespace = true
  timeout          = 600

  values = [
    file("${path.module}/values/metallb.yaml"),
  ]
}

resource "helm_release" "pool" {
  name       = "metallb-pool"
  chart      = "${path.module}/charts/pool"
  namespace  = local.namespace
  timeout    = 300
  depends_on = [helm_release.metallb]

  set = [
    {
      name  = "addressPool"
      value = var.address_pool
    },
  ]
}

output "namespace" {
  description = "Namespace where MetalLB runs."
  value       = local.namespace
}

output "address_pool" {
  description = "Addresses MetalLB can assign to LoadBalancer services."
  value       = var.address_pool
}
