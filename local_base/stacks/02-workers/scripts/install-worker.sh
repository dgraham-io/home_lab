#!/bin/bash
# Install containerd and kubeadm on an Ubuntu worker, then join the control plane.
set -euo pipefail

: "${KUBERNETES_VERSION:?}"
: "${KUBERNETES_APT_KEY_FINGERPRINT:?}"
: "${NODE_NAME:?}"

export DEBIAN_FRONTEND=noninteractive

arch="$(dpkg --print-architecture)"
if [[ "$arch" != "amd64" ]]; then
  echo "Workers expect Ubuntu on amd64; found ${arch}." >&2
  exit 1
fi

if [[ "$(stat -fc %T /sys/fs/cgroup)" != "cgroup2fs" ]]; then
  echo "Ubuntu 24.04 should be using cgroup v2. Found $(stat -fc %T /sys/fs/cgroup)." >&2
  exit 1
fi

install -d -m 0700 /var/lib/home-lab
install -m 0755 /tmp/install-worker.sh /var/lib/home-lab/install-worker.sh
install -m 0600 /tmp/kubeadm-join /var/lib/home-lab/kubeadm-join

install -d -m 0755 /etc/modules-load.d /etc/sysctl.d
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-kubernetes.conf >/dev/null

swapoff -a || true
sed -i -E '/^[^#].*[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab
systemctl disable --now dphys-swapfile >/dev/null 2>&1 || true

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg containerd conntrack socat ebtables ethtool iptables

install -d -m 0755 /etc/containerd
restart_containerd=0
if [[ ! -f /etc/containerd/config.toml ]] || ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  restart_containerd=1
fi
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "containerd config never set SystemdCgroup = true." >&2
  exit 1
fi
systemctl enable containerd
if [[ "$restart_containerd" -eq 1 ]] || ! systemctl is-active --quiet containerd; then
  systemctl restart containerd
fi

minor="${KUBERNETES_VERSION%.*}"
install -d -m 0755 /etc/apt/keyrings
key_ascii="$(mktemp)"
key_tmp="$(mktemp)"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${minor}/deb/Release.key" -o "$key_ascii"
key_info="$(gpg --batch --show-keys --with-colons "$key_ascii")"
actual_fingerprint="$(awk -F: '/^fpr:/ { print $10; exit }' <<< "$key_info")"
if [[ "$actual_fingerprint" != "$KUBERNETES_APT_KEY_FINGERPRINT" ]]; then
  echo "Kubernetes apt key fingerprint ${actual_fingerprint:-unknown} does not match ${KUBERNETES_APT_KEY_FINGERPRINT}." >&2
  exit 1
fi
gpg --batch --dearmor < "$key_ascii" > "$key_tmp"
install -m 0644 "$key_tmp" /etc/apt/keyrings/kubernetes-apt-keyring.gpg
rm -f "$key_ascii" "$key_tmp"
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${minor}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update

if command -v kubeadm >/dev/null; then
  installed="$(kubeadm version -o short)"
  if [[ "$installed" != "v${KUBERNETES_VERSION}" ]]; then
    echo "kubeadm ${installed} is installed; refusing to change a live worker to v${KUBERNETES_VERSION}." >&2
    exit 1
  fi
else
  madison="$(apt-cache madison kubeadm)"
  package_version="$(awk -v want="${KUBERNETES_VERSION}-" '$3 ~ "^" want { print $3; exit }' <<< "$madison")"
  if [[ -z "$package_version" ]]; then
    echo "kubeadm ${KUBERNETES_VERSION} is not in the pkgs.k8s.io repository." >&2
    exit 1
  fi
  apt-get install -y \
    "kubelet=${package_version}" \
    "kubeadm=${package_version}" \
    "kubectl=${package_version}"
fi
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable kubelet

ufw_status="$(ufw status 2>/dev/null || true)"
if command -v ufw >/dev/null && [[ "$ufw_status" == *"Status: active"* ]]; then
  addr_lines="$(ip -4 -o addr show scope global)"
  lan_cidr="$(awk 'NR==1 { print $4 }' <<< "$addr_lines")"
  if [[ -n "$lan_cidr" ]]; then
    ufw allow from "$lan_cidr" to any port 10250 proto tcp comment "kubelet"
    ufw allow from "$lan_cidr" to any port 8472 proto udp comment "flannel vxlan"
  fi
fi

if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  echo "${NODE_NAME} is already joined; leaving the kubelet in place"
  exit 0
fi

read -r -a join_args < /var/lib/home-lab/kubeadm-join
"${join_args[@]}" \
  --node-name "$NODE_NAME" \
  --cri-socket unix:///run/containerd/containerd.sock
