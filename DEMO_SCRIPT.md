# Guardium MOK Enrollment - Demo Talk Track

## Before You Start

### One-Time Setup
```bash
./setup.sh    # Creates VM, ~5-10 min (only run once)
```

### Pre-Demo Checklist
- [ ] Run `./test.sh` to verify VM boots, SSH, Secure Boot, VNC all pass
- [ ] Terminal font size large enough for audience
- [ ] Position your terminal and VMware Fusion windows side by side
- [ ] During the demo, the **VM console window** shows live proof - make sure audience can see it

### After Computer Restart
```bash
cd ~/Desktop/MOK-Demo
./demo.sh
```
That's it. No need to re-run setup.

---

## Opening (Banner Screen)

> "Today I'm going to show you a fully automated solution for Machine Owner Key enrollment for Guardium on Secure Boot-enabled Linux servers."
>
> "This is a real problem at every enterprise running RHEL, Ubuntu, or SUSE with Secure Boot. Guardium's kernel module gets blocked because it's not signed by a trusted key. The traditional fix requires a human to physically interact with each server's boot menu. That doesn't scale."
>
> "What you're about to see is **zero-touch, fully automated MOK enrollment**. And I'll prove it's real - you'll watch everything happen live in the VM console."

**Press ENTER to begin.**

---

## VM Boots (VMware Fusion Window Opens)

The demo opens the VM with a visible console window. Position it where the audience can see.

> "This is a real Ubuntu server running in VMware Fusion with UEFI Secure Boot enabled. Not a recording, not a simulation. You can see the server console right there."

---

## Phase 1: The Problem

The demo builds the Guardium kernel module, then logs into the VM console via automated keystrokes. The audience sees two things at once:

**In the VM console window:**
```
========================================
  Secure Boot Status Check
========================================
SecureBoot enabled

========================================
  Loading Guardium - BEFORE MOK
========================================
insmod: ERROR: could not insert module ... Operation not permitted
```

**In the terminal:**
```
BLOCKED by Secure Boot - module signature not trusted
```

### Talk Track

When Secure Boot status appears:

> "First, let's confirm Secure Boot is active on this server. You can see it right there in the VM console - `SecureBoot enabled`."

When the insmod error appears:

> "Now we try to load the Guardium agent. Watch the VM console."
>
> **[Pause - let audience read the error]**
>
> "'Operation not permitted.' The kernel refuses to load our module because it isn't signed by a trusted key. Look at the console - that's the real error, on a real server."
>
> "This is what your server admins deal with on every Guardium deployment where Secure Boot is active. The traditional fix: someone walks up to the server, reboots it, waits for the MOK Manager screen, manually navigates menus, types a password, and reboots again. Per server. Now imagine doing that across 500 or 2,000 servers."

**Press ENTER to continue.**

---

## Phase 2: The Automated Fix

### Steps 1-2: Certificate and Import

> "First, we generate an X.509 certificate and sign the Guardium module with it. Standard Linux kernel module signing. Then `mokutil --import` queues the certificate for enrollment in the server's firmware."

### Before Reboot - "WATCH THE VM CONSOLE" Prompt

The demo pauses with a yellow box telling the audience to watch the VM window. This is the money shot.

> "Now here's the key moment. I'm about to reboot this server. **Watch the VM console window.** You're going to see the MOK Manager boot screen appear - that's the UEFI menu that normally requires a human at the keyboard. Our automation will navigate it completely hands-free."

**Press ENTER to trigger the reboot.**

### Steps 3-4: Reboot + MokManager Automation

The audience watches the VM console window show:
1. Server shutting down
2. UEFI firmware loading
3. **Blue MokManager screen appearing**
4. Menu items being selected automatically (Enroll MOK > Continue > Yes)
5. Password being typed automatically
6. Server rebooting

> "There it is. The MOK Manager appeared, and our automation navigated every menu, typed the enrollment password, and confirmed - all through **hypervisor keystroke injection**. No human touched that console."
>
> "This works on any hypervisor that supports console injection: VMware vSphere, KVM/libvirt, Hyper-V, even cloud platforms with serial console access."

### Steps 5-6: Reboot and Verification

> "The server is rebooting with the new key enrolled in firmware. When it comes back, the kernel will trust our Guardium certificate."

When "MOK Certificate enrolled" appears:

> "Confirmed. Our Guardium Security Agent certificate is now in the firmware's trust store."

---

## Phase 3: The Moment of Truth

The demo pauses before loading the module.

> "Same server. Same module. Same Secure Boot. The only difference: our certificate is now enrolled. Let's try loading Guardium again."

**Press ENTER.**

The demo loads the module via SSH, then logs into the VM console to display proof. The audience sees:

**In the VM console window:**
```
========================================
  Loading Guardium - AFTER MOK
========================================
(no error!)

Module status:
guardium_agent    16384  0

Kernel logs:
Guardium: Security agent loaded successfully
Guardium: Monitoring database activity...
```

> **[Pause - let audience read the console]**
>
> "**It loads.** Look at the VM console. No error. `lsmod` shows Guardium active in the kernel. And the kernel logs: 'Security agent loaded successfully. Monitoring database activity.'"
>
> "That's the same command that was blocked 2 minutes ago. Same server, same Secure Boot enforcement. The only thing we changed was enrolling our certificate - completely automated."

---

## Summary Screen

Point to the before/after comparison:

> "Before: blocked. After: running."

Point to the automation stats:

> "**Zero manual steps.** About two minutes per server. And because servers run in parallel, the wall clock time doesn't increase whether you're doing 2 servers or 2,000."

Point to business value:

> "For your organization, this means:
> - No more scheduling maintenance windows for MOK enrollment
> - No more sending technicians to data centers
> - No more inconsistent enrollment across your fleet
> - Guardium deploys on Secure Boot servers just as easily as non-Secure Boot"

The VM is still running at this point - offer to let the audience inspect it or ask questions.

**Press ENTER to shut down and end.**

---

## Anticipated Questions

**Q: Does this work on VMware vSphere in production?**
> "Yes. VMware's VIX API and vSphere SDK both support console keystroke injection. The demo uses VMware Fusion locally, but the same approach applies to vSphere at scale."

**Q: What about physical servers (not VMs)?**
> "For bare metal, two paths: IPMI/BMC console redirection for out-of-band keystroke injection, or pre-staging the MOK certificate in the firmware via UEFI provisioning tools during initial server deployment."

**Q: Is this secure? Are we bypassing Secure Boot?**
> "No, we're working *with* Secure Boot, not around it. We enroll a certificate through the official UEFI MOK mechanism. The key is stored in the firmware's trust store, and every module load is still signature-verified. We've automated the human interaction, not the security."

**Q: What if the MOK password is intercepted?**
> "The MOK enrollment password is single-use and only valid during that one boot cycle. It's generated per-enrollment and never stored. Even if intercepted, it can't be reused."

**Q: How does this handle kernel updates?**
> "Once the MOK certificate is enrolled, it persists across kernel updates. You only re-sign the module when you rebuild it for a new kernel version. The certificate stays trusted in firmware."

**Q: What Linux distributions does this support?**
> "Any distribution that uses shim + MOK for Secure Boot: Ubuntu, RHEL, SUSE, Fedora, Debian. The MOK infrastructure is standardized across all of them."

**Q: Can we see the VM console to verify this is real?**
> "Absolutely - the VM is still running. Feel free to come look." *(VM stays running until you press ENTER to shut down.)*
