# Observability

Prometheus, Alertmanager, Grafana, node-exporter, and kube-state-metrics for any cluster that has a kubeconfig. The release is the `kube-prometheus-stack` chart. Applications add their own `ServiceMonitor` objects. This stack does not scrape them by editing the chart.

```bash
cd observability
terraform init
terraform apply -var kubeconfig_path=../local_base/stacks/01-control-plane/.generated/admin.conf
```

Grafana and Prometheus are LoadBalancer services. MetalLB, installed by `local_base`, assigns each one an address from its pool. Grafana is port 80 and Prometheus is port 9090.

```bash
kubectl -n monitoring get svc monitoring-grafana monitoring-kube-prometheus-prometheus
```

```bash
terraform output -raw grafana_admin_password
```

Log in as `admin`. Metrics are stored in emptyDir, so they are discarded when Prometheus restarts.
