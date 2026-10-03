#!/bin/bash
# Open the ports a kubeadm control plane needs when UFW is already enabled.
# Does not enable UFW. A host with UFW inactive is left unchanged.
set -euo pipefail

if ! command -v ufw >/dev/null; then
  echo "ufw is not installed; leaving the host firewall unchanged"
  exit 0
fi

ufw_status="$(ufw status 2>/dev/null || true)"
if [[ "$ufw_status" != *"Status: active"* ]]; then
  echo "ufw is not active; leaving the host firewall unchanged"
  exit 0
fi

if [[ -z "${LAN_CIDR:-}" ]]; then
  addr_lines="$(ip -4 -o addr show scope global)"
  LAN_CIDR="$(awk '$2 != "flannel.1" { print $4; exit }' <<< "$addr_lines")"
fi
lan="${LAN_CIDR:-192.168.1.0/24}"
pod="${POD_CIDR:-10.244.0.0/16}"
svc="${SERVICE_CIDR:-10.96.0.0/12}"

if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
  sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

ufw allow 22/tcp comment "ssh"
ufw allow from "$lan" to any port 6443 proto tcp comment "kubernetes api"
ufw allow from "$lan" to any port 2379:2380 proto tcp comment "etcd"
ufw allow from "$lan" to any port 2381 proto tcp comment "etcd metrics"
ufw allow from "$lan" to any port 10250 proto tcp comment "kubelet"
ufw allow from "$lan" to any port 10257 proto tcp comment "kube-controller-manager"
ufw allow from "$lan" to any port 10259 proto tcp comment "kube-scheduler"
ufw allow from "$lan" to any port 10249 proto tcp comment "kube-proxy metrics"
ufw allow from "$lan" to any port 9100 proto tcp comment "node-exporter"
ufw allow from "$lan" to any port 8472 proto udp comment "flannel vxlan"
ufw allow from "$lan" to any port 7946 proto tcp comment "metallb memberlist"
ufw allow from "$lan" to any port 7946 proto udp comment "metallb memberlist"
ufw allow from "$lan" to any port 30000:32767 proto tcp comment "nodeports"
ufw allow from "$pod" comment "pods"
ufw allow from "$svc" comment "services"
ufw reload
ufw status verbose
