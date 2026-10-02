#!/bin/bash
# After prepare-node.sh requests a reboot, wait until the new kernel cmdline is active.
set -euo pipefail

: "${SSH_KEY:?}"
: "${SSH_TARGET:?}"

ssh_base=(
  ssh
  -i "$SSH_KEY"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o BatchMode=yes
  -o ConnectTimeout=5
)

if ! status="$("${ssh_base[@]}" "$SSH_TARGET" 'if sudo -n test -f /var/lib/home-lab/reboot-required; then echo yes; else echo no; fi')"; then
  echo "ssh to ${SSH_TARGET} failed before the reboot check" >&2
  exit 1
fi

if [[ "$status" != "yes" ]]; then
  exit 0
fi

echo "waiting for ${SSH_TARGET} to reboot with memory cgroups enabled"
for _ in $(seq 1 90); do
  if "${ssh_base[@]}" "$SSH_TARGET" 'grep -Eq "(^|[[:space:]])cgroup_memory=1([[:space:]]|$)" /proc/cmdline && grep -Eq "(^|[[:space:]])cgroup_enable=memory([[:space:]]|$)" /proc/cmdline'; then
    exit 0
  fi
  sleep 5
done

echo "timed out waiting for ${SSH_TARGET} to reboot" >&2
exit 1
