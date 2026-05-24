#Requires -RunAsAdministrator

# YellowKey mitigation (CVE-2026-45585): add TPM+PIN protector to BitLocker
# Targets all BitLocker-protected drives by default, or a specific drive via -Drive.

param(
    [string]$Drive = ""
)

$ErrorActionPreference = "Stop"

# --- Check Windows version ---
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 22000) {
    Write-Host "Windows 10 detected (build $build) — not affected by YellowKey. Exiting." -ForegroundColor Green
    exit 0
}

# --- Collect target volumes ---
if ($Drive) {
    $mountPoint = $Drive.TrimEnd('\') + ":"
    $volumes = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction SilentlyContinue
    if (-not $volumes) {
        Write-Error "Drive $mountPoint not found or BitLocker module unavailable."
        exit 1
    }
} else {
    $volumes = Get-BitLockerVolume -ErrorAction SilentlyContinue |
        Where-Object { $_.ProtectionStatus -eq "On" }
    if (-not $volumes) {
        Write-Host "No BitLocker-protected drives found." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "BitLocker-protected drives found:" -ForegroundColor Cyan
$volumes | ForEach-Object { Write-Host "  $($_.MountPoint)  $($_.VolumeStatus)  Protection: $($_.ProtectionStatus)" }
Write-Host ""

# --- Apply Group Policy registry keys once (required or manage-bde rejects TPM+PIN) ---
$fvePath = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
if (-not (Test-Path $fvePath)) { New-Item -Path $fvePath -Force | Out-Null }

Set-ItemProperty -Path $fvePath -Name "UseAdvancedStartup" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $fvePath -Name "UseTPMPIN"          -Value 2 -Type DWord -Force
Set-ItemProperty -Path $fvePath -Name "UseTPM"             -Value 2 -Type DWord -Force
Set-ItemProperty -Path $fvePath -Name "UseEnhancedPin"     -Value 1 -Type DWord -Force

Write-Host "Group Policy keys set. Refreshing policy..." -ForegroundColor Cyan
gpupdate /force | Out-Null
Write-Host ""

# --- Process each drive ---
foreach ($vol in $volumes) {
    $mp = $vol.MountPoint

    Write-Host "==============================" -ForegroundColor DarkGray
    Write-Host "Drive: $mp" -ForegroundColor White
    Write-Host "==============================" -ForegroundColor DarkGray

    # TPM+PIN only makes sense on the OS drive — data drives use password or recovery key protectors.
    # Warn and skip non-OS drives that lack a TPM protector.
    $hasTpm = (Get-BitLockerVolume -MountPoint $mp).KeyProtector |
        Where-Object { $_.KeyProtectorType -in @("Tpm", "TpmPin", "TpmKey", "TpmKeyPin") }

    if (-not $hasTpm) {
        Write-Host "$mp has no TPM protector — TPM+PIN applies to the OS drive only. Skipping." -ForegroundColor Yellow
        Write-Host ""
        continue
    }

    $alreadyHasTpmPin = (Get-BitLockerVolume -MountPoint $mp).KeyProtector |
        Where-Object { $_.KeyProtectorType -eq "TpmPin" }

    if ($alreadyHasTpmPin) {
        Write-Host "$mp already has a TPM+PIN protector — already mitigated against YellowKey." -ForegroundColor Green
        Write-Host ""
        continue
    }

    Write-Host "Adding TPM+PIN protector. You will be prompted for a PIN." -ForegroundColor Cyan
    Write-Host "PIN must be 6+ characters. Alphanumeric is supported." -ForegroundColor Gray
    Write-Host ""

    manage-bde -protectors -add $mp -TPMAndPIN

    Write-Host ""
    Write-Host "Current protectors on $mp`:" -ForegroundColor Cyan
    manage-bde -protectors -get $mp

    $tpmOnlyId = (Get-BitLockerVolume -MountPoint $mp).KeyProtector |
        Where-Object { $_.KeyProtectorType -eq "Tpm" } |
        Select-Object -ExpandProperty KeyProtectorId

    if ($tpmOnlyId) {
        Write-Host ""
        Write-Host "TPM-only protector found: $tpmOnlyId" -ForegroundColor Yellow
        $confirm = Read-Host "Remove TPM-only protector on $mp? This leaves only TPM+PIN. (y/N)"
        if ($confirm -eq "y") {
            manage-bde -protectors -delete $mp -id $tpmOnlyId
            Write-Host "TPM-only protector removed." -ForegroundColor Green
        } else {
            Write-Host "Skipped. Remove manually with:" -ForegroundColor Gray
            Write-Host "  manage-bde -protectors -delete $mp -id $tpmOnlyId" -ForegroundColor Gray
        }
    } else {
        Write-Host "No TPM-only protector found — nothing to clean up." -ForegroundColor Green
    }

    Write-Host ""
}

Write-Host "Done. Verify with: manage-bde -status <drive>" -ForegroundColor Green
