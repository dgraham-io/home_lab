terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

variable "kubeconfig_path" {
  description = "Admin kubeconfig for the cluster that will run this stack."
  type        = string
}

variable "chart_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "91.9.0"
}

locals {
  namespace = "monitoring"
}

resource "random_password" "grafana_admin" {
  length           = 24
  special          = true
  override_special = "-_."
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  namespace        = local.namespace
  create_namespace = true
  timeout          = 900

  values = [
    file("${path.module}/values/kube-prometheus-stack.yaml"),
  ]

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana_admin.result
    },
  ]
}

output "namespace" {
  description = "Namespace where the monitoring stack runs."
  value       = local.namespace
}

output "grafana_admin_user" {
  description = "Grafana admin user."
  value       = "admin"
}

output "grafana_admin_password" {
  description = "Grafana admin password. Read it with terraform output -raw grafana_admin_password."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "service_addresses" {
  description = "LoadBalancer addresses assigned to Grafana (port 80) and Prometheus (port 9090)."
  value       = "kubectl --kubeconfig ${var.kubeconfig_path} --namespace ${local.namespace} get svc monitoring-grafana monitoring-kube-prometheus-prometheus"
}
