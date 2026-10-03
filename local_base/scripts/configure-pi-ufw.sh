#!/bin/bash
# Apply the control-plane UFW rules to an already running Pi.
# Usage: configure-pi-ufw.sh <pi-host> <ssh-user>
set -euo pipefail

host="${1:?usage: $0 <pi-host> <ssh-user>}"
user="${2:?usage: $0 <pi-host> <ssh-user>}"
script="$(cd "$(dirname "$0")/../stacks/01-control-plane/scripts" && pwd)/configure-ufw.sh"

ssh -t "${user}@${host}" "sudo bash -s" < "$script"
