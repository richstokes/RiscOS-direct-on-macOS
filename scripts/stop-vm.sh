#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-2222}"
SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PASSWORD="${SSH_PASSWORD:-ubuntu}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

usage() {
  cat <<'USAGE'
Usage: scripts/stop-vm.sh [--force]

Gracefully shuts down the local QEMU guest over SSH.

Options:
  --force   Kill matching qemu-system-aarch64 processes if graceful shutdown fails.

Environment:
  SSH_PORT          SSH forwarded port, default 2222
  SSH_HOST          SSH host, default 127.0.0.1
  SSH_USER          SSH user, default ubuntu
  SSH_PASSWORD      SSH password for expect fallback, default ubuntu
  TIMEOUT_SECONDS   Seconds to wait for poweroff, default 60
USAGE
}

force=0
case "${1:-}" in
  "")
    ;;
  --force)
    force=1
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

port_open() {
  nc -z "$SSH_HOST" "$SSH_PORT" >/dev/null 2>&1
}

shutdown_over_ssh() {
  if ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p "$SSH_PORT" \
    "$SSH_USER@$SSH_HOST" \
    'sudo shutdown -h now'; then
    return 0
  fi

  if command -v expect >/dev/null 2>&1; then
    expect <<EOF
set timeout 30
spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "sudo shutdown -h now"
expect {
  -re ".*assword:.*" {
    send "$SSH_PASSWORD\r"
    exp_continue
  }
  eof
}
EOF
    return 0
  fi

  return 1
}

force_kill_qemu() {
  local pids
  pids="$(pgrep -f 'qemu-system-aarch64.*riscos-direct' || true)"
  if [[ -z "$pids" ]]; then
    pids="$(pgrep -f 'qemu-system-aarch64.*riscos-ubuntu-arm64.qcow2' || true)"
  fi

  if [[ -z "$pids" ]]; then
    printf 'No matching RISC OS Direct QEMU process found.\n'
    return 1
  fi

  printf 'Killing QEMU process(es): %s\n' "$pids"
  kill $pids
}

if ! port_open; then
  printf 'SSH port %s:%s is not reachable; VM may already be stopped.\n' "$SSH_HOST" "$SSH_PORT"
  if [[ "$force" -eq 1 ]]; then
    force_kill_qemu || true
  fi
  exit 0
fi

printf 'Requesting graceful shutdown over SSH...\n'
if ! shutdown_over_ssh; then
  printf 'Could not request shutdown over SSH.\n' >&2
  if [[ "$force" -eq 1 ]]; then
    force_kill_qemu || true
    exit 0
  fi
  printf 'Run again with --force to kill the matching QEMU process.\n' >&2
  exit 1
fi

printf 'Waiting for VM to stop'
deadline=$((SECONDS + TIMEOUT_SECONDS))
while port_open; do
  if (( SECONDS >= deadline )); then
    printf '\nTimed out waiting for SSH port to close.\n' >&2
    if [[ "$force" -eq 1 ]]; then
      force_kill_qemu || true
      exit 0
    fi
    printf 'Run again with --force to kill the matching QEMU process.\n' >&2
    exit 1
  fi
  printf '.'
  sleep 1
done

printf '\nVM stopped.\n'
