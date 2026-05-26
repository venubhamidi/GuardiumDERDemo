#!/bin/bash
# setup.sh - VMware Fusion setup for MOK Demo
# Run this ONCE before customer demo

set -e

# VMware Fusion paths
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
VDISK="/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager"
OVFTOOL="/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"

DEMO_DIR="$HOME/Desktop/MOK-Demo"
VM_BUNDLE="$DEMO_DIR/guardium.vmwarevm"
VMX="$VM_BUNDLE/guardium.vmx"
SSH_KEY="$DEMO_DIR/demo_key"

OVA_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova"

# Helper: get VM IP (vmrun + DHCP lease fallback)
get_vm_ip() {
    local vmx="$1"
    local ip
    # Try VMware Tools first
    ip=$("$VMRUN" getGuestIPAddress "$vmx" 2>/dev/null)
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "$ip"
        return 0
    fi
    # Fallback: parse DHCP leases for guardium-server
    ip=$(awk '/^lease /{ip=$2} /guardium-server/{found=ip} END{print found}' \
        /var/db/vmware/vmnet-dhcpd-vmnet8.leases 2>/dev/null)
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "$ip"
        return 0
    fi
    echo ""
    return 1
}

echo "╔════════════════════════════════════════════════════════╗"
echo "║  MOK Demo Setup - VMware Fusion + Secure Boot         ║"
echo "║  This will take 5-10 minutes                          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

cd "$DEMO_DIR"

# ── Step 1: Generate SSH key ──────────────────────────────
if [ ! -f "$SSH_KEY" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
    echo "  ✓ SSH key generated"
fi

# ── Step 2: Download Ubuntu cloud image OVA ───────────────
if [ ! -f "ubuntu-22.04-cloudimg.ova" ]; then
    echo "Downloading Ubuntu 22.04 cloud image OVA (~680MB)..."
    curl -L --progress-bar "$OVA_URL" -o ubuntu-22.04-cloudimg.ova
    echo "  ✓ Download complete"
else
    echo "  ✓ Ubuntu OVA already downloaded"
fi

# ── Step 3: Import OVA and create VM ─────────────────────
echo "Creating VM from OVA..."

# Remove old VM if exists
if [ -d "$VM_BUNDLE" ]; then
    "$VMRUN" stop "$VMX" hard 2>/dev/null || true
    sleep 2
    rm -rf "$VM_BUNDLE"
fi

"$OVFTOOL" --name=guardium "$DEMO_DIR/ubuntu-22.04-cloudimg.ova" "$DEMO_DIR/"
echo "  ✓ VM created from OVA"

# ── Step 4: Configure VMX for Secure Boot + VNC ──────────
echo "Configuring VM for Secure Boot..."

# Find the VMX file (ovftool may name it differently)
VMX=$(find "$VM_BUNDLE" -name "*.vmx" | head -1)

# Enable Secure Boot and VNC
cat >> "$VMX" << 'VMXEOF'

# MOK Demo additions
firmware = "efi"
uefi.secureBoot.enabled = "TRUE"
RemoteDisplay.vnc.enabled = "TRUE"
RemoteDisplay.vnc.port = "5901"
memsize = "2048"
numvcpus = "2"
VMXEOF

echo "  ✓ Secure Boot enabled"
echo "  ✓ VNC enabled on port 5901"

# ── Step 5: Create cloud-init cidata ISO ─────────────────
echo "Creating cloud-init configuration..."
PUBKEY=$(cat "$SSH_KEY.pub")

cat > user-data << EOF
#cloud-config
hostname: guardium-server
users:
  - name: demo
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: demo
    ssh_authorized_keys:
      - ${PUBKEY}
package_update: true
packages:
  - mokutil
  - openssl
  - build-essential
  - linux-headers-generic
  - open-vm-tools
  - flex
  - bison
  - keyutils
runcmd:
  - mkdir -p /root/mok-demo
EOF

cat > meta-data << 'METAEOF'
instance-id: demo-vm
local-hostname: guardium-server
METAEOF

rm -f cidata.iso
mkdir -p cidata-dir
cp user-data meta-data cidata-dir/
hdiutil makehybrid -o cidata.iso -joliet -iso \
  -default-volume-name cidata cidata-dir
rm -rf cidata-dir
echo "  ✓ Cloud-init ISO created"

# Attach cidata ISO as CD-ROM
cat >> "$VMX" << EOF
ide1:0.present = "TRUE"
ide1:0.deviceType = "cdrom-image"
ide1:0.fileName = "$DEMO_DIR/cidata.iso"
ide1:0.startConnected = "TRUE"
EOF
echo "  ✓ Cloud-init ISO attached"

# ── Step 6: Start VM and wait for provisioning ───────────
echo ""
echo "Starting VM..."
"$VMRUN" start "$VMX" nogui
echo "  ✓ VM started"

echo "  Waiting for VM to get IP address..."
VM_IP=""
for attempt in $(seq 1 30); do
    sleep 10
    VM_IP=$(get_vm_ip "$VMX")
    if [ -n "$VM_IP" ]; then
        echo "  ✓ VM IP: $VM_IP"
        break
    fi
    if [ $attempt -eq 30 ]; then
        echo "  ⚠ Timeout waiting for IP. VM may still be booting."
        echo "  Try: $VMRUN getGuestIPAddress \"$VMX\""
        exit 1
    fi
done

# Save IP for other scripts
echo "$VM_IP" > "$DEMO_DIR/vm_ip"

# Wait for SSH
echo "  Waiting for SSH..."
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
for attempt in $(seq 1 12); do
    sleep 5
    if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "echo ok" 2>/dev/null >/dev/null; then
        echo "  ✓ SSH ready"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "  ⚠ SSH timeout"
        exit 1
    fi
done

# Wait for cloud-init
echo "  Waiting for cloud-init to finish..."
for attempt in $(seq 1 24); do
    sleep 10
    if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP \
        "cloud-init status 2>/dev/null | grep -q done" 2>/dev/null; then
        echo "  ✓ Cloud-init complete"
        break
    fi
    if [ $attempt -eq 24 ]; then
        echo "  ⚠ Cloud-init timeout (may still be running)"
    fi
done

# ── Step 7: Verify ───────────────────────────────────────
echo ""
echo "Verifying installation..."

ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP \
    "which mokutil >/dev/null 2>&1 && echo '  ✓ mokutil installed' || echo '  ✗ mokutil not found'" 2>/dev/null
ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP \
    "which flex >/dev/null 2>&1 && echo '  ✓ flex installed' || echo '  ✗ flex not found'" 2>/dev/null

# Check Secure Boot status
echo ""
echo "Checking Secure Boot status..."
SB_STATE=$(ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "mokutil --sb-state 2>&1" 2>/dev/null)
echo "  $SB_STATE"

if echo "$SB_STATE" | grep -qi "enabled"; then
    echo "  ✓ Secure Boot is ENABLED - real MOK enrollment will work!"
else
    echo "  ⚠ Secure Boot not enabled. Checking firmware..."
    ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "cat /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | xxd | head -3" 2>/dev/null
fi

# ── Step 8: Shut down VM ────────────────────────────────
echo ""
echo "Shutting down VM..."
"$VMRUN" stop "$VMX" soft 2>/dev/null || "$VMRUN" stop "$VMX" hard 2>/dev/null || true
sleep 3

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✓ SETUP COMPLETE!                                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "VM: $VM_BUNDLE"
echo "IP: $VM_IP (saved to vm_ip)"
echo "SSH: ssh -i $SSH_KEY demo@$VM_IP"
echo ""
echo "Next steps:"
echo "  1. Test VM: ./test.sh"
echo "  2. Run customer demo: ./demo.sh"
echo ""
