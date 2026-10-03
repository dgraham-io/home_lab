#!/bin/bash
# Ask the control plane for a fresh kubeadm join command.
set -euo pipefail

: "${SSH_KEY:?}"
: "${SSH_TARGET:?}"
: "${JOIN_COMMAND_PATH:?}"

ssh_base=(
  ssh
  -i "$SSH_KEY"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o BatchMode=yes
  -o ConnectTimeout=5
)

install -d -m 0700 -- "$(dirname -- "$JOIN_COMMAND_PATH")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

"${ssh_base[@]}" "$SSH_TARGET" 'sudo -n kubeadm token create --print-join-command' > "$tmp"
if ! grep -q '^kubeadm join ' "$tmp"; then
  echo "control plane did not return a kubeadm join command" >&2
  exit 1
fi

install -m 0600 "$tmp" "$JOIN_COMMAND_PATH"
