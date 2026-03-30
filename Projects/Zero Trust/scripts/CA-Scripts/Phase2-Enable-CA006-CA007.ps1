<#
.SYNOPSIS
    PHASE 2 — Week 8: Enable CA006 & CA007 (Device Compliance Enforced)
.DESCRIPTION
    Activates device compliance after all devices confirmed enrolled and compliant.
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) already excluded by policy.
.PARAMETER CA006Id
    Object ID of CA006 from Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1
.PARAMETER CA007Id
    Object ID of CA007 from Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.NOTES
    Versetal | Phase 2 Week 8 | Gantt milestone: Device Compliance Enforced
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][string]$CA006Id,
    [Parameter(Mandatory=$true)][string]$CA007Id,
    [Parameter(Mandatory=$false)][string]$TenantId
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
Write-Host "  PHASE 2 Week 8: Enable CA006 & CA007" -ForegroundColor Cyan
Write-Host "  MILESTONE: Device Compliance Enforced" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Checklist before enabling:" -ForegroundColor Yellow
Write-Host "  [ ] All Windows/macOS devices show Compliant in Intune" -ForegroundColor White
Write-Host "  [ ] Zero devices in Grace Period — all remediations complete" -ForegroundColor White
Write-Host "  [ ] Intune App Protection Policies deployed for iOS/Android" -ForegroundColor White
Write-Host "  [ ] Test user on iOS confirmed can access Outlook via MAM" -ForegroundColor White
Write-Host "  [ ] Test user on Android confirmed can access Outlook via MAM" -ForegroundColor White
Write-Host "  [ ] Helpdesk briefed on compliance block remediation steps" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Type YES to confirm and enable CA006 & CA007"
if ($confirm -ne "YES") { Write-Host "  Aborted." -ForegroundColor Red; exit 0 }

Connect-Graph -TenantId $TenantId -Scopes @("Policy.ReadWrite.ConditionalAccess","Policy.Read.All")
Assert-BreakGlass

Enable-Policy -Label "CA006 - Require compliant device for cloud apps"       -PolicyId $CA006Id
Enable-Policy -Label "CA007 - Require app protection policy for mobile"       -PolicyId $CA007Id

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  MILESTONE COMPLETE: Phase 2 Device Compliance Active" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Validate:" -ForegroundColor Yellow
Write-Host "  1. Compliant device -> confirm access granted" -ForegroundColor White
Write-Host "  2. Unmanaged device -> confirm blocked/redirected" -ForegroundColor White
Write-Host "  3. Personal phone   -> confirm MAM app required" -ForegroundColor White
Write-Host ""
Write-Host "  Phase 3 is Purview/MCAS work (no CA scripts)." -ForegroundColor Cyan
Write-Host "  CA010 deploys in Phase 4 once MCAS session policy is configured." -ForegroundColor Cyan
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
