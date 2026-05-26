# MOK-Demo — Zero-Touch MOK Enrollment for Guardium on Secure Boot

A live demonstration of fully automated **Machine Owner Key (MOK)** enrollment for the Guardium kernel module on a UEFI Secure Boot-enabled Linux server. The traditional MOK enrollment flow requires a human to sit at each server's boot menu, navigate the blue MokManager screen, and type the enrollment password by hand. This demo replaces that human with **hypervisor-level keystroke injection over VNC**, making the entire flow scriptable across thousands of servers.

The demo runs end-to-end on a Mac with VMware Fusion: it builds a real Ubuntu 22.04 VM with UEFI + Secure Boot, compiles a mock Guardium kernel module, shows it being **blocked** by Secure Boot, signs it with a freshly generated X.509 certificate, enrolls the certificate through MokManager via automated VNC keystrokes, reboots, and demonstrates the same module now **loading successfully**.

## Requirements

- macOS with **VMware Fusion** installed (uses `vmrun`, `ovftool`, `vmware-vdiskmanager`)
- Python 3 (used by `vnc_keys.py` — no pip dependencies)
- `ssh`, `scp`, `openssl`, `curl`, `hdiutil` (all preinstalled on macOS)
- ~10 GB free disk space (Ubuntu OVA + VM disk)
- Outbound internet (to download the Ubuntu 22.04 cloud image OVA on first setup)

## Files

| File | Purpose |
|---|---|
| `setup.sh` | One-time setup. Downloads the Ubuntu OVA, creates the VM, enables Secure Boot + VNC in the VMX, generates an SSH key, builds a cloud-init ISO, and provisions the guest with required packages (`mokutil`, `openssl`, kernel headers, etc.). |
| `demo.sh` | The customer-facing demo. Runs the three-phase flow: show the problem → automate MOK enrollment → verify the module loads. |
| `test.sh` | Pre-demo sanity check. Boots the VM and verifies SSH, `mokutil`, kernel headers, Secure Boot state, and VNC keystroke injection. |
| `vnc_keys.py` | Pure-Python RFB/VNC client that sends keystrokes to the VM console on port 5901. Used to drive MokManager at boot time. |
| `DEMO_SCRIPT.md` | Presenter talk track. Phase-by-phase script with anticipated audience questions. |

## Quick Start

```bash
# One-time setup (~5–10 min, downloads ~680 MB Ubuntu OVA)
./setup.sh

# Sanity-check before going live
./test.sh

# Run the demo
./demo.sh
```

After `setup.sh` finishes, the VM is configured with:
- UEFI firmware with Secure Boot **enabled**
- VNC server on `localhost:5901` (no auth, local-only)
- A `demo` user with passwordless sudo and your generated SSH key
- All packages needed to compile and sign kernel modules

## How the Automation Works

1. **Build & sign.** `demo.sh` compiles a small Guardium kernel module on the guest, generates an X.509 cert with `openssl`, and signs the `.ko` with the kernel's `sign-file` tool.
2. **Queue enrollment.** `mokutil --import` registers the DER cert for enrollment on next boot and stores a one-time password.
3. **Reboot.** The guest reboots into MokManager (the blue UEFI menu).
4. **Inject keystrokes.** `vnc_keys.py` connects to VMware Fusion's VNC port and sends the exact sequence MokManager expects: `SPACE` to enter the menu during the countdown, then `DOWN`/`ENTER` to navigate **Enroll MOK → Continue → Yes**, then types the password, then `ENTER` to reboot.
5. **Verify.** After the second boot, `mokutil --list-enrolled` confirms the cert is in the firmware trust store, and `insmod` now loads the signed module without error.

The same approach generalizes beyond VMware Fusion: VMware vSphere (VIX/SDK), KVM/libvirt (`virsh send-key`), Hyper-V, and cloud serial consoles all support equivalent keystroke injection.

## Security Notes

- This demo **works with** Secure Boot, not around it. The certificate is enrolled through the standard UEFI MOK mechanism; every module load is still signature-verified by the kernel.
- The MOK enrollment password is single-use and only valid for one boot cycle. It cannot be replayed.
- `demo_key` (the SSH private key) and `demo_key.pub` are **gitignored**. They are generated locally by `setup.sh` and should never be committed.
- The VM's `demo` user has passwordless sudo — this is a throwaway demo VM, not a production configuration.

## Cleanup

```bash
# Stop the VM
"/Applications/VMware Fusion.app/Contents/Library/vmrun" stop \
  ~/Desktop/MOK-Demo/guardium.vmwarevm/guardium.vmx hard

# Full reset — delete VM and downloaded artifacts
rm -rf ~/Desktop/MOK-Demo/guardium.vmwarevm
rm -f ~/Desktop/MOK-Demo/{ubuntu-22.04-cloudimg.ova,cidata.iso,vm_ip,demo_key,demo_key.pub,user-data,meta-data}
```

Re-run `./setup.sh` to rebuild from scratch.
