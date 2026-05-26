#!/bin/bash
# test.sh - Quick verification that VM is working with VMware Fusion

VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
DEMO_DIR="$HOME/Desktop/MOK-Demo"
VM_BUNDLE="$DEMO_DIR/guardium.vmwarevm"
VMX=$(find "$VM_BUNDLE" -name "*.vmx" | head -1)
SSH_KEY="$DEMO_DIR/demo_key"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

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

echo "╔════════════════════════════════════════╗"
echo "║  VM Verification Test (VMware Fusion) ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Start VM
echo "Starting VM..."
"$VMRUN" start "$VMX" nogui 2>/dev/null || true

# Get IP
echo "  Waiting for boot..."
VM_IP=""
for attempt in $(seq 1 20); do
    sleep 5
    VM_IP=$(get_vm_ip "$VMX")
    if [ -n "$VM_IP" ]; then
        echo "  ✓ VM IP: $VM_IP"
        echo "$VM_IP" > "$DEMO_DIR/vm_ip"
        break
    fi
    if [ $attempt -eq 20 ]; then
        echo "  ✗ Timeout waiting for IP"
        exit 1
    fi
done

# Wait for SSH
for attempt in $(seq 1 12); do
    sleep 5
    if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "echo ok" 2>/dev/null >/dev/null; then
        echo "  ✓ SSH working"
        break
    fi
    if [ $attempt -eq 12 ]; then
        echo "  ✗ SSH failed"
        "$VMRUN" stop "$VMX" hard 2>/dev/null || true
        exit 1
    fi
done

# Test mokutil
if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "which mokutil" 2>/dev/null >/dev/null; then
    echo "  ✓ mokutil installed"
else
    echo "  ✗ mokutil not found"
fi

# Test flex
if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "which flex" 2>/dev/null >/dev/null; then
    echo "  ✓ flex installed"
else
    echo "  ✗ flex not found"
fi

# Test kernel headers
if ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP \
   "ls /usr/src/linux-headers-\$(uname -r) >/dev/null 2>&1" 2>/dev/null; then
    echo "  ✓ kernel headers installed"
else
    echo "  ✗ kernel headers not found"
fi

# Check Secure Boot
SB_STATE=$(ssh -i "$SSH_KEY" $SSH_OPTS demo@$VM_IP "mokutil --sb-state 2>&1" 2>/dev/null)
echo "  Secure Boot: $SB_STATE"

# Check VNC
echo ""
echo "Testing VNC keystroke injection..."
if python3 "$DEMO_DIR/vnc_keys.py" localhost 5901 key space 2>/dev/null; then
    echo "  ✓ VNC keystroke injection working"
else
    echo "  ✗ VNC connection failed (port 5901)"
fi

# Stop VM
echo ""
echo "Stopping VM..."
"$VMRUN" stop "$VMX" soft 2>/dev/null || "$VMRUN" stop "$VMX" hard 2>/dev/null || true
echo ""
echo "✓ Test complete!"
