#!/bin/bash
# Enable the Pi kernel memory controller, then let Terraform reboot once if the running kernel lacks it.
set -euo pipefail

has_arg() {
  local file="$1"
  local arg="$2"
  grep -Eq "(^|[[:space:]])${arg}([[:space:]]|$)" "$file"
}

install -d -m 0700 /var/lib/home-lab
install -m 0755 /tmp/prepare-node.sh /var/lib/home-lab/prepare-node.sh
install -m 0755 /tmp/install-control-plane.sh /var/lib/home-lab/install-control-plane.sh
install -m 0600 /tmp/kubeadm-config.yaml /var/lib/home-lab/kubeadm-config.yaml
install -m 0644 /tmp/kube-flannel.yml /var/lib/home-lab/kube-flannel.yml

if [[ -f /boot/firmware/cmdline.txt ]]; then
  cmdline_file=/boot/firmware/cmdline.txt
elif [[ -f /boot/cmdline.txt ]]; then
  cmdline_file=/boot/cmdline.txt
else
  echo "Raspberry Pi cmdline file not found. Expected /boot/firmware/cmdline.txt." >&2
  exit 1
fi

for arg in cgroup_enable=memory cgroup_memory=1; do
  if ! has_arg "$cmdline_file" "$arg"; then
    line="$(tr -d '\n' < "$cmdline_file")"
    printf '%s %s\n' "$line" "$arg" > "$cmdline_file"
  fi
done

if has_arg /proc/cmdline cgroup_memory=1 && has_arg /proc/cmdline cgroup_enable=memory; then
  rm -f /var/lib/home-lab/reboot-required
else
  touch /var/lib/home-lab/reboot-required
  echo "memory cgroups are not active; the Pi will reboot once before kubeadm init"
fi
