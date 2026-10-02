#!/bin/bash
# Copy the admin kubeconfig and the worker join command back to the Terraform machine.
set -euo pipefail

: "${SSH_KEY:?}"
: "${SSH_TARGET:?}"
: "${KUBECONFIG_PATH:?}"
: "${JOIN_COMMAND_PATH:?}"

ssh_base=(
  ssh
  -i "$SSH_KEY"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o BatchMode=yes
  -o ConnectTimeout=5
)

umask 077
install -d -m 0700 -- "$(dirname -- "$KUBECONFIG_PATH")"
install -d -m 0700 -- "$(dirname -- "$JOIN_COMMAND_PATH")"

tmp_kube="$(mktemp)"
tmp_join="$(mktemp)"
trap 'rm -f "$tmp_kube" "$tmp_join"' EXIT

"${ssh_base[@]}" "$SSH_TARGET" 'sudo -n cat /etc/kubernetes/admin.conf' > "$tmp_kube"
"${ssh_base[@]}" "$SSH_TARGET" 'sudo -n cat /var/lib/home-lab/join-command' > "$tmp_join"

if [[ ! -s "$tmp_kube" || ! -s "$tmp_join" ]]; then
  echo "remote kubeconfig or join command was empty" >&2
  exit 1
fi

mv "$tmp_kube" "$KUBECONFIG_PATH"
mv "$tmp_join" "$JOIN_COMMAND_PATH"
chmod 600 "$KUBECONFIG_PATH" "$JOIN_COMMAND_PATH"
