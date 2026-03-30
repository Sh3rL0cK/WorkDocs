<#
.SYNOPSIS
    PHASE 2 — Week 7: Deploy CA006 & CA007 (Device Compliance, Report-only)
.DESCRIPTION
    CA006 — Require compliant device for cloud apps (Windows/macOS MDM)
    CA007 — Require app protection policy for mobile (iOS/Android MAM-WE)
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) are hardcoded and auto-excluded.

    CRITICAL: Do NOT enable CA006 before Intune enrollment is complete.
    CA006 = Windows/macOS only (MDM). iOS/Android handled by CA007 (MAM, no MDM needed).
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.PARAMETER PolicyState
    Default: "enabledForReportingButNotEnforced"
.NOTES
    Versetal | Phase 2 Week 7 | Gantt: Deploy Week 7 -> Enable Week 8
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)][string]$TenantId,
    [Parameter(Mandatory=$false)]
    [ValidateSet("enabledForReportingButNotEnforced","enabled","disabled")]
    [string]$PolicyState = "enabledForReportingButNotEnforced"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region ── VERSETAL BREAK-GLASS ACCOUNTS (hardcoded — do not modify) ────────────
# These accounts are excluded from ALL Conditional Access policies.
# vers_azbtg01@versetalinfo.onmicrosoft.com  |  1f24d999-5644-44a9-a79e-a6d2d83ec2e4
# vers_azbtg02@versetalinfo.onmicrosoft.com  |  430380e1-b2c6-4d1f-a56b-0fc776839b1c
$BTG = @(
    "1f24d999-5644-44a9-a79e-a6d2d83ec2e4",   # vers_azbtg01@versetalinfo.onmicrosoft.com
    "430380e1-b2c6-4d1f-a56b-0fc776839b1c"    # vers_azbtg02@versetalinfo.onmicrosoft.com
)
#endregion

function Connect-Graph {
    param([string]$TenantId, [string[]]$Scopes)
    if (-not (Get-Module -ListAvailable -Name "Microsoft.Graph.Identity.SignIns")) {
        Write-Host "  Installing Microsoft.Graph module..." -ForegroundColor Yellow
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
    if ($TenantId) {
        Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -NoWelcome
    } else {
        Connect-MgGraph -Scopes $Scopes -NoWelcome
    }
    Write-Host "  Connected: $((Get-MgContext).TenantId)" -ForegroundColor Green
}

function Assert-BreakGlass {
    Write-Host ""
    Write-Host "  Validating break-glass accounts..." -ForegroundColor Cyan
    foreach ($id in $BTG) {
        try {
            $u = Get-MgUser -UserId $id -Property DisplayName,UserPrincipalName
            Write-Host "  + $($u.DisplayName) ($($u.UserPrincipalName))" -ForegroundColor Green
        } catch {
            Write-Host "  !! Break-glass $id NOT FOUND — aborting." -ForegroundColor Red
            exit 1
        }
    }
}

function New-CAPolicy {
    param([string]$Id, [string]$DisplayName, [hashtable]$Body, [string]$License, [string]$Week)
    Write-Host ""
    Write-Host "  -- Deploying $Id : $DisplayName" -ForegroundColor Yellow
    Write-Host "     License : $License  |  Gantt : $Week" -ForegroundColor DarkGray
    try {
        $r = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" `
            -Body ($Body | ConvertTo-Json -Depth 20 -Compress) `
            -ContentType "application/json"
        Write-Host "     Created : $($r.id)" -ForegroundColor Green
        return $r
    } catch {
        Write-Host "     FAILED  : $_" -ForegroundColor Red; throw
    }
}

function Enable-Policy {
    param([string]$Label, [string]$PolicyId)
    Write-Host ""
    Write-Host "  -- Enabling $Label..." -ForegroundColor Yellow
    $cur = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId"
    if ($cur.state -eq "enabled") {
        Write-Host "     Already enabled — skipping" -ForegroundColor Gray; return
    }
    Invoke-MgGraphRequest -Method PATCH `
        -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId" `
        -Body ('{"state":"enabled"}') -ContentType "application/json"
    Write-Host "     ENABLED" -ForegroundColor Green
    Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  PHASE 2 Week 7: Deploy CA006 & CA007 (Device Compliance)" -ForegroundColor Cyan
Write-Host "  CA006 = Windows/macOS MDM compliance" -ForegroundColor Gray
Write-Host "  CA007 = iOS/Android MAM (no MDM enrollment required for BYOD)" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

Connect-Graph -TenantId $TenantId -Scopes @(
    "Policy.ReadWrite.ConditionalAccess","Policy.Read.All","Directory.Read.All")
Assert-BreakGlass

# CA006 — Require compliant device (Windows/macOS only)
# WHY: Verified identity on unmanaged/unpatched device is still a risk.
#      Compliance = BitLocker on, Secure Boot on, OS patched, Defender active.
# PROTECTS: Session token theft/replay from unmanaged devices, unencrypted endpoints.
# NOTE: iOS/Android are EXCLUDED — they are covered by CA007 (MAM-WE).
#       Full MDM on personal phones causes user resistance; MAM-WE is the right approach.
# IMPORTANT: Only enable after ALL Windows/macOS devices show Compliant in Intune.
# GANTT: Deploy Week 7 (Report-only) -> Enable Week 8
$ca006 = New-CAPolicy -Id "CA006" -DisplayName "CA006 - Require compliant device for cloud apps" `
    -License "Microsoft Intune (M365 Business Premium / E3)" -Week "7 (Report-only) -> Enable Week 8" -Body @{
        displayName="CA006 - Require compliant device for cloud apps"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all")
            platforms=@{ includePlatforms=@("windows","macOS") } }
        grantControls=@{ operator="OR"; builtInControls=@("compliantDevice","domainJoinedDevice") } }

# CA007 — App protection policy for iOS/Android (MAM without enrollment)
# WHY: BYOD mobile data protection without requiring full device enrollment.
#      Wraps Outlook/Teams/OneDrive in encrypted container with PIN and selective wipe.
# PROTECTS: Corporate data saved to personal iCloud/Google Drive, copy-paste to personal apps,
#           data exfiltration via native mail apps with no protection controls.
# NOTE: Users install Intune Company Portal and use approved apps. Personal data untouched.
# IMPORTANT: Intune App Protection Policies for iOS/Android must be created in Intune first.
# GANTT: Deploy Week 7 (Report-only) -> Enable Week 8
$ca007 = New-CAPolicy -Id "CA007" -DisplayName "CA007 - Require app protection policy for mobile" `
    -License "Intune App Protection (M365 Business Premium)" -Week "7 (Report-only) -> Enable Week 8" -Body @{
        displayName="CA007 - Require app protection policy for mobile"; state=$PolicyState
        conditions=@{ users=@{ includeUsers=@("All"); excludeUsers=$BTG }
            applications=@{ includeApplications=@("All") }; clientAppTypes=@("all")
            platforms=@{ includePlatforms=@("iOS","android") } }
        grantControls=@{ operator="OR"; builtInControls=@("approvedApplication","compliantApplication") } }

Write-Host ""
Write-Host "  CA006 : $($ca006.id)" -ForegroundColor White
Write-Host "  CA007 : $($ca007.id)" -ForegroundColor White
Write-Host ""
Write-Host "  NEXT: Remediate non-compliant devices, deploy MAM policies, then:" -ForegroundColor Cyan
Write-Host "  Week 8: Run .\Phase2-Enable-CA006-CA007.ps1" -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
