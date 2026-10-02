#!/bin/bash
# Install containerd and kubeadm, initialize the control plane, and install Flannel.
set -euo pipefail

: "${KUBERNETES_VERSION:?}"
: "${POD_CIDR:?}"
: "${KUBERNETES_APT_KEY_FINGERPRINT:?}"

export DEBIAN_FRONTEND=noninteractive

has_arg() {
  local file="$1"
  local arg="$2"
  grep -Eq "(^|[[:space:]])${arg}([[:space:]]|$)" "$file"
}

if ! has_arg /proc/cmdline cgroup_memory=1 || ! has_arg /proc/cmdline cgroup_enable=memory; then
  echo "memory cgroups are not active in /proc/cmdline. Re-run apply so the Pi can reboot." >&2
  exit 1
fi
rm -f /var/lib/home-lab/reboot-required

arch="$(dpkg --print-architecture)"
if [[ "$arch" != "arm64" ]]; then
  echo "This control plane expects 64-bit Raspberry Pi OS (arm64); found ${arch}." >&2
  exit 1
fi

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
systemctl disable --now rpi-swap >/dev/null 2>&1 || true

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
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$key_ascii" | awk -F: '/^fpr:/ { print $10; exit }')"
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
    echo "kubeadm ${installed} is installed; refusing to change a live control plane to v${KUBERNETES_VERSION}." >&2
    exit 1
  fi
else
  package_version="$(apt-cache madison kubeadm | awk -v want="${KUBERNETES_VERSION}-" '$3 ~ "^" want { print $3; exit }')"
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

install -d -m 0755 /etc/kubernetes
install -m 0600 /var/lib/home-lab/kubeadm-config.yaml /etc/kubernetes/kubeadm-config.yaml

if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  kubeadm init --config /etc/kubernetes/kubeadm-config.yaml
else
  echo "control plane already initialized; leaving the API server in place"
fi

export KUBECONFIG=/etc/kubernetes/admin.conf
flannel_manifest=/var/lib/home-lab/kube-flannel.yml
if [[ ! -f "$flannel_manifest" ]]; then
  echo "missing ${flannel_manifest}; the Flannel manifest is copied from this stack before install." >&2
  exit 1
fi
sed -i -E "s#(\"Network\": \")[^\"]+(\")#\\1${POD_CIDR}\\2#" "$flannel_manifest"
if ! grep -q "\"Network\": \"${POD_CIDR}\"" "$flannel_manifest"; then
  echo "failed to set the Flannel network to ${POD_CIDR}" >&2
  exit 1
fi
kubectl apply -f "$flannel_manifest"
kubectl -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=300s
kubectl wait --for=condition=Ready node --all --timeout=300s

umask 077
kubeadm token create --print-join-command > /var/lib/home-lab/join-command
