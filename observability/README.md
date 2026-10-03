# Observability

Prometheus, Alertmanager, Grafana, node-exporter, and kube-state-metrics for any cluster that has a kubeconfig. The release is the `kube-prometheus-stack` chart. Applications add their own `ServiceMonitor` objects. This stack does not scrape them by editing the chart.

```bash
cd observability
terraform init
terraform apply -var kubeconfig_path=../local_base/stacks/01-control-plane/.generated/admin.conf
```

Grafana and Prometheus are NodePorts on every node. From the lab network, use a worker address. The Pi firewall does not allow these ports.

- Grafana: `http://node1:30080` or `http://node2:30080`
- Prometheus: `http://node1:30090` or `http://node2:30090`

```bash
terraform output -raw grafana_admin_password
```

Log in as `admin`. Metrics are stored in emptyDir, so they are discarded when Prometheus restarts.
