<div align="center">

# 🔐 yellowkey-mitigation

### BitLocker TPM+PIN Hardening Against CVE-2026-45585 (YellowKey)

**Automated mitigation for the WinRE BitLocker bypass — no full patch available yet**

[![CVE](https://img.shields.io/badge/CVE-2026--45585-red.svg)](https://nvd.nist.gov/vuln/detail/CVE-2026-45585)
[![Platform](https://img.shields.io/badge/Platform-Windows%2011%20%2F%20Server%202025-0078D4.svg)](https://www.microsoft.com/en-us/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](https://learn.microsoft.com/en-us/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

---

## 🔍 The Vulnerability

**YellowKey** is a publicly disclosed BitLocker bypass that gives an attacker with physical access an unrestricted shell on a BitLocker-protected Windows 11 drive — without the recovery key, without the PIN, and without any credentials.

A component inside the Windows Recovery Environment (`autofstx.exe`) performs a Transactional NTFS replay routine that deletes `winpeshl.ini`. The side-effect is a shell that launches with full access to the decrypted volume. The attacker triggers it by copying a folder to a USB drive (or directly to the EFI partition), rebooting into WinRE, and holding CTRL.

| | Details |
|---|---|
| **CVE** | [CVE-2026-45585](https://nvd.nist.gov/vuln/detail/CVE-2026-45585) |
| **CVSS Score** | 6.8 (Medium) |
| **CVSS Vector** | `CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H` |
| **CWE** | CWE-77 (Command Injection) |
| **Attack Vector** | Physical access required |
| **Published** | May 19, 2026 |
| **Patch** | None yet — Microsoft issued manual mitigation only |
| **MSRC Advisory** | [msrc.microsoft.com/update-guide/vulnerability/CVE-2026-45585](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-45585) |
| **PoC** | Publicly available ([Nightmare-Eclipse/YellowKey](https://github.com/Nightmare-Eclipse/YellowKey)) |
| **Affected** | Windows 11 (24H2, 25H2, 26H1), Windows Server 2022/2025 |
| **Not affected** | Windows 10 |

---

## 💡 The Mitigation

Switching from **TPM-only** to **TPM+PIN** blocks the attack entirely. With a PIN required at boot, the attacker cannot decrypt the drive regardless of how the WinRE shell is spawned — the TPM will not release the volume master key without the correct PIN.

> **TPM-only BitLocker** unlocks automatically on any boot of the same hardware. TPM+PIN requires a secret only the user knows, closing the YellowKey gap.

The script handles the Group Policy prerequisites that block `manage-bde` from adding a PIN protector by default, then safely transitions the drive from TPM-only to TPM+PIN in a single run.

---

## ⚡ What the Script Does

```
  Run Add-BitLockerTPMPin.ps1 (admin)
       │
       ▼
  [Version Check] ──→ exits gracefully on Windows 10 (not affected)
       │
       ▼
  [BitLocker Status Check] ──→ confirms encryption is active on C:
       │
       ▼
  [Group Policy Fix] ──→ sets UseAdvancedStartup + UseTPMPIN + UseEnhancedPin
       │                   (required — manage-bde rejects TPM+PIN without these)
       ▼
  [gpupdate /force] ──→ applies policy immediately without reboot
       │
       ▼
  [manage-bde -protectors -add C: -TPMAndPIN] ──→ prompts for PIN interactively
       │
       ▼
  [List Protectors] ──→ shows all current protectors for verification
       │
       ▼
  [Remove TPM-only Protector] ──→ optional, prompted with confirmation
```

---

## 🚀 Quick Start

### Requirements

- Windows 11 (24H2 or later) or Windows Server 2022/2025
- BitLocker enabled on C:
- Administrator privileges
- Recovery key accessible before running (store it in your Microsoft account or print it)

### Run

```powershell
# Run these as two separate commands in an elevated PowerShell prompt:
Set-ExecutionPolicy Bypass -Scope Process -Force
```
```powershell
# All BitLocker-protected drives (auto-detected):
.\Add-BitLockerTPMPin.ps1

# Or target a specific drive:
.\Add-BitLockerTPMPin.ps1 -Drive C
.\Add-BitLockerTPMPin.ps1 -Drive D
```

You will be prompted interactively to set a PIN per drive. Alphanumeric PINs are supported (the script enables enhanced PINs via registry).

> **Note:** TPM+PIN protectors apply to the **OS drive only** (the drive that boots through the TPM). Data drives (D:, E:, etc.) use password or recovery key protectors — the script will detect and skip them automatically.

---

## 📖 Usage

### Interactive flow

```
BitLocker-protected drives found:
  C:\  FullyEncrypted  Protection: On
  D:\  FullyEncrypted  Protection: On

Group Policy keys set. Refreshing policy...

==============================
Drive: C:\
==============================
Adding TPM+PIN protector. You will be prompted for a PIN.
PIN must be 6+ characters. Alphanumeric is supported.

Type the PIN to use to protect the volume:
Confirm the PIN by typing it again:
Key Protectors Added:
  TPM And PIN:
    ID: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}

Current protectors on C:\:
  ...

TPM-only protector found: {YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY}
Remove TPM-only protector on C:\? This leaves only TPM+PIN. (y/N): y
TPM-only protector removed.

==============================
Drive: D:\
==============================
D:\ has no TPM protector — TPM+PIN applies to the OS drive only. Skipping.

Done. Verify with: manage-bde -status <drive>
```

### Verify after running

```powershell
manage-bde -status C:
# Should show: Key Protectors: TPM And PIN
# Protection Status: Protection On
```

---

## 🛡️ Security Notes

**Have your recovery key before running.** The script removes the TPM-only protector only after confirming the TPM+PIN protector was added successfully, but if the machine is rebooted mid-run or the `manage-bde -add` step partially fails, you will need the recovery key to unlock the drive.

**Retrieve your recovery key now:**

```powershell
# Print recovery key to console (store it somewhere safe)
manage-bde -protectors -get C: -Type RecoveryPassword
```

Or find it in your Microsoft account at [account.microsoft.com/devices/recoverykey](https://account.microsoft.com/devices/recoverykey).

**PIN choice matters.** A short numeric PIN offers weak protection against targeted physical attacks. Use at least 8 characters. Alphanumeric PINs are enabled by the script.

---

## ⚙️ What the Group Policy Keys Do

The script sets four registry values under `HKLM:\SOFTWARE\Policies\Microsoft\FVE`:

| Key | Value | Purpose |
|---|---|---|
| `UseAdvancedStartup` | `1` | Enables the "Require additional authentication at startup" policy — without this, all `UseTPM*` keys are ignored |
| `UseTPMPIN` | `2` | `0` = block, `1` = require, `2` = allow TPM+PIN |
| `UseTPM` | `2` | Allows TPM-only alongside PIN (prevents policy conflicts) |
| `UseEnhancedPin` | `1` | Allows alphanumeric characters in the PIN |

These are the exact keys that Windows Group Policy (gpedit.msc) writes. Setting them via registry is equivalent to configuring the policy through the MMC snap-in.

---

## 🔧 Manual Steps (no script)

If you prefer to run the steps individually:

```powershell
# 1. Set Group Policy registry keys
$p = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
if (-not (Test-Path $p)) { New-Item -Path $p -Force }
Set-ItemProperty -Path $p -Name "UseAdvancedStartup" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $p -Name "UseTPMPIN"          -Value 2 -Type DWord -Force
Set-ItemProperty -Path $p -Name "UseTPM"             -Value 2 -Type DWord -Force
Set-ItemProperty -Path $p -Name "UseEnhancedPin"     -Value 1 -Type DWord -Force
gpupdate /force

# 2. Add TPM+PIN protector
manage-bde -protectors -add C: -TPMAndPIN

# 3. Find the TPM-only protector ID
manage-bde -protectors -get C:

# 4. Remove it (replace GUID with the ID from step 3)
manage-bde -protectors -delete C: -id {YOUR-TPM-ONLY-GUID}

# 5. Verify
manage-bde -status C:
```

---

## 🗂️ Repository Structure

```
yellowkey-mitigation/
├── Add-BitLockerTPMPin.ps1   # Main mitigation script
└── README.md
```

---

## 🤖 AI Acknowledgment

This script was co-developed with **Claude (Anthropic)**. All logic was reviewed and tested on Windows 11 by the author.

---

## 📄 License

[MIT](https://opensource.org/licenses/MIT) — Free to use, modify, and distribute.

---

<div align="center">

© 2026 Andrei Majer

[![GitHub](https://img.shields.io/badge/GitHub-andrei--majer-181717?logo=github)](https://github.com/andrei-majer) [![LinkedIn](https://img.shields.io/badge/LinkedIn-Andrei%20Majer-0A66C2?logo=linkedin)](https://www.linkedin.com/in/andrei-majer/)

</div>
