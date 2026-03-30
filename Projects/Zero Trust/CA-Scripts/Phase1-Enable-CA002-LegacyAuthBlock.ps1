<#
.SYNOPSIS
    PHASE 1 — Week 3: Enable CA002 (Block Legacy Authentication)
.DESCRIPTION
    Activates CA002 after the 30-day legacy auth audit is complete.
    This is always the FIRST policy you enable — before CA001 or any other.
    Break-glass accounts (vers_azbtg01@versetalinfo.onmicrosoft.com, vers_azbtg02@versetalinfo.onmicrosoft.com) are already excluded by policy.
.PARAMETER PolicyId
    Object ID of CA002 from Phase1-Deploy-CA001-CA002-CA003-CA008-CA009.ps1
.PARAMETER TenantId
    Entra ID tenant ID. Optional if already connected.
.NOTES
    Versetal | Phase 1 Week 3 | Gantt milestone: Enable CA002
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][string]$PolicyId,
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
Write-Host "  PHASE 1 Week 3: Enable CA002 - Block Legacy Authentication" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pre-flight checklist — type YES only when all are done:" -ForegroundColor Yellow
Write-Host "  [ ] Reviewed 30 days of Sign-in logs for 'Other clients'" -ForegroundColor White
Write-Host "  [ ] Reviewed 30 days of Sign-in logs for 'Exchange ActiveSync'" -ForegroundColor White
Write-Host "  [ ] All printers/scanners/apps using Basic Auth identified" -ForegroundColor White
Write-Host "  [ ] Basic Auth dependencies migrated or exceptions documented" -ForegroundColor White
Write-Host "  [ ] Helpdesk notified — users may call if a legacy app breaks" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "  Type YES to confirm and enable CA002"
if ($confirm -ne "YES") { Write-Host "  Aborted." -ForegroundColor Red; exit 0 }

Connect-Graph -TenantId $TenantId -Scopes @("Policy.ReadWrite.ConditionalAccess","Policy.Read.All")
Assert-BreakGlass

Enable-Policy -Label "CA002 - Block legacy authentication" -PolicyId $PolicyId

Write-Host ""
Write-Host "  CA002 is ENABLED. Legacy authentication is now blocked." -ForegroundColor Green
Write-Host ""
Write-Host "  Monitor: Entra ID > Sign-in logs > Filter CA Result = Failure > CA002" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NEXT: Run .\Phase1-Deploy-CA004-CA005-RiskPolicies.ps1" -ForegroundColor White
Write-Host ""
Write-Host ""
Write-Host "  !! TEST BREAK-GLASS ACCOUNTS NOW !!" -ForegroundColor Red
Write-Host "     vers_azbtg01@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host "     vers_azbtg02@versetalinfo.onmicrosoft.com" -ForegroundColor DarkRed
Write-Host ""
Disconnect-MgGraph | Out-Null
