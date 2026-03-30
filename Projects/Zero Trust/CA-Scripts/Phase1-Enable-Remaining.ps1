<#
.SYNOPSIS
    PHASE 1 — Week 4: Enable CA001, CA003, CA008, CA009, CA004, CA005
.DESCRIPTION
    Activates all remaining Phase 1 policies after the Report-only review period.
    CA002 should already be enabled (Week 3). Enables in safe order:
      CA001 -> CA003 -> CA008 -> CA009 -> CA004 -> CA005
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) already excluded by policy.
.PARAMETER PolicyIds
    Hashtable of policy Object IDs from the deploy scripts.
    Example:
      -PolicyIds @{
          CA001="guid"; CA003="guid"; CA004="guid"
          CA005="guid"; CA008="guid"; CA009="guid"
      }
.PARAMETER SkipRiskPolicies
    Skip CA004/CA005 if Entra ID P2 licensing is not yet confirmed.
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.NOTES
    Versetal | Phase 1 Week 4 | Gantt milestone: Enable CA001 CA003 CA008 CA009 CA004 CA005
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][hashtable]$PolicyIds,
    [Parameter(Mandatory=$false)][switch]$SkipRiskPolicies,
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
Write-Host "  PHASE 1 Week 4: Enable All Phase 1 Policies" -ForegroundColor Cyan
Write-Host "  MILESTONE: Phase 1 Identity Hardening Complete" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Final checklist before enabling:" -ForegroundColor Yellow
Write-Host "  [ ] CA002 already enabled (legacy auth blocked — Week 3 done)" -ForegroundColor White
Write-Host "  [ ] 14+ days of Report-only data reviewed, no unexpected blocks" -ForegroundColor White
Write-Host "  [ ] All admin accounts have FIDO2 keys / WHfB enrolled (CA003)" -ForegroundColor White
Write-Host "  [ ] Named Locations configured in Entra ID (CA008)" -ForegroundColor White
Write-Host "  [ ] Both break-glass accounts tested and confirmed working:" -ForegroundColor White
Write-Host "        vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "        vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkGray
Write-Host "  [ ] Helpdesk briefed — MFA enforcement goes live today" -ForegroundColor White
Write-Host "  [ ] User communication sent" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Type YES to confirm checklist and enable all policies"
if ($confirm -ne "YES") { Write-Host "  Aborted." -ForegroundColor Red; exit 0 }

Connect-Graph -TenantId $TenantId -Scopes @("Policy.ReadWrite.ConditionalAccess","Policy.Read.All")
Assert-BreakGlass

Enable-Policy -Label "CA001 - Require MFA for all users"             -PolicyId $PolicyIds.CA001
Enable-Policy -Label "CA003 - Phishing-resistant MFA for admins"     -PolicyId $PolicyIds.CA003
Enable-Policy -Label "CA008 - MFA from untrusted locations"          -PolicyId $PolicyIds.CA008
Enable-Policy -Label "CA009 - MFA for Azure management"              -PolicyId $PolicyIds.CA009

if (-not $SkipRiskPolicies) {
    Enable-Policy -Label "CA004 - Block high-risk sign-ins"           -PolicyId $PolicyIds.CA004
    Write-Host "  Pausing 10s before CA005 — monitor for unexpected risk alerts..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
    Enable-Policy -Label "CA005 - Password change for high-risk users" -PolicyId $PolicyIds.CA005
} else {
    Write-Host ""
    Write-Host "  Skipped CA004/CA005 (SkipRiskPolicies set — enable once P2 confirmed)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  MILESTONE COMPLETE: Phase 1 Identity Hardening Active" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Validate now:" -ForegroundColor Yellow
Write-Host "  1. Sign in as test user — confirm MFA is prompted" -ForegroundColor White
Write-Host "  2. Sign in as test admin — confirm FIDO2/WHfB is required" -ForegroundColor White
Write-Host "  3. Attempt legacy auth connection — confirm blocked" -ForegroundColor White
Write-Host "  4. Sign in as both break-glass accounts — confirm still works" -ForegroundColor White
Write-Host ""
Write-Host "  PHASE 2 begins Week 5 — run: .\Phase2-Deploy-CA006-CA007-DeviceCompliance.ps1" -ForegroundColor Cyan
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
