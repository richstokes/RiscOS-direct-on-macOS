#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS="$ROOT/downloads"
VM_DIR="$ROOT/vm"
SEED_DIR="$VM_DIR/seed"

UBUNTU_BASE_URL="${UBUNTU_BASE_URL:-https://cloud-images.ubuntu.com/releases/24.04/release}"
UBUNTU_IMAGE_NAME="${UBUNTU_IMAGE_NAME:-ubuntu-24.04-server-cloudimg-arm64.img}"
UBUNTU_IMAGE_URL="${UBUNTU_IMAGE_URL:-$UBUNTU_BASE_URL/$UBUNTU_IMAGE_NAME}"
BASE_IMAGE="$DOWNLOADS/$UBUNTU_IMAGE_NAME"
SHA_FILE="$DOWNLOADS/SHA256SUMS"

DISK="$VM_DIR/riscos-ubuntu-arm64.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
DISK_SIZE="${DISK_SIZE:-32G}"

usage() {
  cat <<'USAGE'
Usage: scripts/create-vm.sh [--force]

Creates:
  downloads/ubuntu-24.04-server-cloudimg-arm64.img
  vm/riscos-ubuntu-arm64.qcow2
  vm/seed.iso

Use --force to recreate the qcow2 disk and seed ISO.

This is a fully local QEMU VM. The Ubuntu "cloudimg" name means a
preinstalled generic qcow2 image, not a remote cloud service.
USAGE
}

force=0
if [[ "${1:-}" == "--force" ]]; then
  force=1
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  printf 'qemu-img was not found. Install QEMU first:\n  brew install qemu\n' >&2
  exit 1
fi

mkdir -p "$DOWNLOADS" "$VM_DIR" "$SEED_DIR"

if [[ ! -f "$BASE_IMAGE" ]]; then
  printf 'Downloading Ubuntu ARM64 prebuilt qcow2 image for local QEMU...\n'
  curl --fail --location --output "$BASE_IMAGE" "$UBUNTU_IMAGE_URL"
fi

printf 'Fetching Ubuntu SHA256SUMS...\n'
curl --fail --location --output "$SHA_FILE" "$UBUNTU_BASE_URL/SHA256SUMS"
(cd "$DOWNLOADS" && grep "$UBUNTU_IMAGE_NAME\$" SHA256SUMS | shasum -a 256 -c -)

if [[ $force -eq 1 ]]; then
  rm -f "$DISK" "$SEED_ISO"
fi

if [[ ! -f "$DISK" ]]; then
  printf 'Creating VM disk %s...\n' "$DISK"
  cp "$BASE_IMAGE" "$DISK"
  qemu-img resize "$DISK" "$DISK_SIZE"
else
  printf 'Using existing VM disk %s\n' "$DISK"
fi

cat > "$SEED_DIR/meta-data" <<'EOF'
instance-id: riscos-direct
local-hostname: riscos-direct
EOF

{
  cat <<'EOF'
#cloud-config
hostname: riscos-direct
manage_etc_hosts: true
ssh_pwauth: true
disable_root: true
users:
  - name: ubuntu
    gecos: RISC OS Direct
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: false
chpasswd:
  expire: false
  users:
    - {name: ubuntu, password: ubuntu, type: text}
package_update: true
package_upgrade: false
packages:
  - openssh-server
  - sudo
write_files:
  - path: /usr/local/bin/riscos-direct
    owner: root:root
    permissions: '0755'
    content: |
EOF
  sed 's/^/      /' "$ROOT/scripts/guest-bootstrap-riscos.sh"
  cat <<'EOF'
  - path: /etc/systemd/system/riscos-direct-vnc.service
    owner: root:root
    permissions: '0644'
    content: |
EOF
  sed 's/^/      /' "$ROOT/scripts/riscos-direct-vnc.service"
  cat <<'EOF'
runcmd:
  - [bash, -lc, 'systemctl enable ssh --now']
  - [bash, -lc, 'systemctl daemon-reload']
  - [bash, -lc, 'systemctl enable --now riscos-direct-vnc.service']
final_message: "Local RISC OS Direct QEMU VM bootstrap finished after $UPTIME seconds. SSH: ssh -p 2222 ubuntu@localhost, VNC: vnc://localhost:5901"
EOF
} > "$SEED_DIR/user-data"

rm -f "$SEED_ISO"
if command -v hdiutil >/dev/null 2>&1; then
  hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$SEED_ISO" "$SEED_DIR"
elif command -v genisoimage >/dev/null 2>&1; then
  genisoimage -quiet -output "$SEED_ISO" -volid cidata -joliet -rock "$SEED_DIR"
else
  printf 'Need hdiutil or genisoimage to create cloud-init seed.iso.\n' >&2
  exit 1
fi

printf '\nVM created.\n'
printf 'Start it with:\n  %s/scripts/start-vm.sh\n' "$ROOT"
printf 'First boot downloads/builds Direct; watch it with:\n  ssh -p 2222 ubuntu@localhost "tail -f ~/riscos-direct-bootstrap.log"\n'
